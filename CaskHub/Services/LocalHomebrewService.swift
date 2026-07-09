//
//  LocalHomebrewService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/04/2026.
//

import AppKit
import Foundation
import Observation

// MARK: - Public Types

/// Snapshot of one locally-installed cask, derived from its INSTALL_RECEIPT.json.
struct LocalCaskInstallation: Hashable, Identifiable, Sendable {
    let token: String
    let installedVersion: String
    let installedAt: Date?
    let appBundleNames: [String]

    var id: String { token }
}

/// Which background action is currently running for a given cask, if any.
enum CaskAction: Equatable, Sendable {
    case opening
    case installing
    case updating
    case uninstalling

    var inProgressLabel: String {
        switch self {
        case .opening:      return "Opening…"
        case .installing:   return "Installing…"
        case .updating:     return "Updating…"
        case .uninstalling: return "Uninstalling…"
        }
    }
}

enum LocalHomebrewError: LocalizedError {
    case brewBinaryNotFound
    case caskroomNotFound
    case appBundleNotFound(token: String)
    case brewCommandFailed(args: [String], exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .brewBinaryNotFound:
            return "Couldn't locate the brew binary. Is Homebrew installed?"
        case .caskroomNotFound:
            return "Couldn't locate the Homebrew Caskroom."
        case .appBundleNotFound(let token):
            return "Couldn't find an installed app for \(token)."
        case .brewCommandFailed(let args, let code, let stderr):
            let cmd = (["brew"] + args).joined(separator: " ")
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "`\(cmd)` failed (exit \(code))."
                : "`\(cmd)` failed (exit \(code)): \(trimmed)"
        }
    }
}

// MARK: - LocalHomebrewService

/// Single source of truth for *this Mac's* local Homebrew cask state.
///
/// - Detection is filesystem-only (reads `Caskroom/<token>/.metadata/INSTALL_RECEIPT.json`),
///   so it's fast and doesn't require `brew` to be in PATH.
/// - Mutations (`uninstall`, `upgrade`) shell out to the real `brew` binary so its
///   bookkeeping stays consistent.
/// - All public state is observed through `@Observable`; views auto-redraw on changes.
@MainActor
@Observable
final class LocalHomebrewService {
    /// Token → installation snapshot. Repopulated by `refresh()`.
    private(set) var installedCasks: [String: LocalCaskInstallation] = [:]

    /// Token → currently-running action, used by views to show spinners and disable buttons.
    private(set) var inFlightActions: [String: CaskAction] = [:]

    /// Tokens whose install is still in the download phase — the only window
    /// where cancelling is guaranteed residual-free (nothing staged yet).
    private(set) var cancellableDownloads: Set<String> = []

    /// Tokens the user asked to cancel; cleared when the process exits.
    private(set) var cancelRequested: Set<String> = []

    /// Token → live brew process, kept for cancellation. Not UI state.
    @ObservationIgnored private var runningProcesses: [String: Process] = [:]

    /// Token → most recent error message from a failed action. Cleared on the next attempt.
    private(set) var actionErrors: [String: String] = [:]

    /// Last successful refresh timestamp; nil before the first scan completes.
    private(set) var lastRefresh: Date?

    /// Most recent error from `refresh()` itself (e.g. Caskroom missing).
    private(set) var refreshError: LocalHomebrewError?

    /// Installed Homebrew version ("4.6.15"), fetched once on first refresh.
    private(set) var brewVersion: String?

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Detection

    /// Re-scans the Caskroom directory and rebuilds `installedCasks`.
    /// Cheap (~ms for typical installs) — safe to call after every action.
    func refresh() async {
        let fm = fileManager
        if brewVersion == nil {
            brewVersion = await Self.fetchBrewVersion()
        }
        let result = await Task.detached(priority: .userInitiated) {
            Self.scanCaskroom(fileManager: fm)
        }.value

        switch result {
        case .success(let casks):
            installedCasks = casks
            refreshError = nil
        case .failure(let error):
            refreshError = error
        }
        lastRefresh = .now
    }

    func isInstalled(token: String) -> Bool {
        installedCasks[token] != nil
    }

    /// Clears the stored error for a token (called when the user dismisses the error alert).
    func clearError(for token: String) {
        actionErrors[token] = nil
    }

    /// TODO (Learning Mode contribution #1): Implement version comparison.
    ///
    /// Homebrew cask versions are NOT strict semver. Examples seen in the wild:
    ///   - `"125.0"`           — clean
    ///   - `"125.0,build42"`   — comma suffix is the build/revision
    ///   - `"125.0_1"`         — underscore suffix is the cask revision
    ///   - `"2024.10.13"`      — date-based
    ///   - `"1.2.3-beta"`      — hyphen suffix
    ///
    /// You have three reasonable strategies:
    ///
    ///   1. **String equality** (5 lines, current placeholder):
    ///        return installation.installedVersion != remoteVersion
    ///      Simplest. Occasionally noisy when only the revision suffix changes.
    ///
    ///   2. **Normalized comparison** (~8 lines):
    ///      Strip everything after the first `,` or `_` on both sides, then compare.
    ///      Fewer false positives, slightly more code.
    ///
    ///   3. **Full semver parsing**:
    ///      Probably overkill — many casks aren't semver at all.
    ///
    /// The decision shapes how often the "Updates" sidebar will flash counts at
    /// the user. Pick the one whose trade-offs feel right for CaskHub, then
    /// replace the body below.
    func isOutdated(token: String, remoteVersion: String) -> Bool {
        guard let installation = installedCasks[token] else { return false }
        return installation.installedVersion != remoteVersion
    }

    /// Single source of truth for "should this cask show an Update button / appear
    /// in the Updates sidebar?" Combines the version check with the auto-update
    /// exclusion so every caller gets the same answer.
    ///
    /// Casks with `autoUpdates == true` (BetterDisplay, Wireshark, etc.) handle
    /// their own updates outside Homebrew — matching `brew outdated --cask`
    /// (non-greedy, the default) and Applite's default behavior.
    func hasAvailableUpdate(token: String, remoteVersion: String, autoUpdates: Bool?) -> Bool {
        autoUpdates != true && isOutdated(token: token, remoteVersion: remoteVersion)
    }

    // MARK: - Actions

    /// Returns true when the cask installs at least one `.app` bundle that we
    /// can launch. CLI-only casks (e.g. `android-platform-tools`) return false
    /// and the UI should not show an Open button for them.
    func canOpenApp(token: String) -> Bool {
        installedCasks[token]?.appBundleNames.isEmpty == false
    }

    /// Launches the installed app via `NSWorkspace`. Errors are written to
    /// `actionErrors[token]` so the view has one consistent error path.
    func openApp(token: String) {
        actionErrors[token] = nil

        guard let installation = installedCasks[token] else {
            actionErrors[token] = LocalHomebrewError.appBundleNotFound(token: token).errorDescription
            return
        }

        let candidates = installation.appBundleNames.flatMap { name -> [URL] in
            [
                URL(fileURLWithPath: "/Applications").appendingPathComponent(name),
                fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent("Applications")
                    .appendingPathComponent(name)
            ]
        }

        guard let appURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            actionErrors[token] = LocalHomebrewError.appBundleNotFound(token: token).errorDescription
            return
        }

        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    /// Runs `brew install --cask <token>`. Refreshes local state on success.
    func install(token: String) async throws {
        try await runMutation(.installing, token: token, args: ["install", "--cask", token])
    }

    /// Runs `brew uninstall --cask <token>`. Refreshes local state on success.
    func uninstall(token: String) async throws {
        try await runMutation(.uninstalling, token: token, args: ["uninstall", "--cask", token])
    }

    /// Runs `brew upgrade --cask <token>`. Refreshes local state on success.
    func upgrade(token: String) async throws {
        try await runMutation(.updating, token: token, args: ["upgrade", "--cask", token])
    }

    /// Cancels an in-flight install. Only honored during the download phase —
    /// once brew starts staging files, cancelling could leave a broken install.
    /// Sends SIGINT to brew and its children (curl); escalates to SIGTERM if
    /// the tree hasn't exited after 5 seconds.
    func cancelInstall(token: String) {
        guard cancellableDownloads.contains(token),
              let process = runningProcesses[token] else { return }
        cancelRequested.insert(token)
        cancellableDownloads.remove(token)

        let pid = process.processIdentifier
        Task.detached(priority: .userInitiated) {
            Self.signalTree(pid: pid, signal: SIGINT)
            try? await Task.sleep(for: .seconds(5))
            if process.isRunning { process.terminate() }
        }
    }

    // MARK: - Mutation Plumbing

    private func runMutation(_ action: CaskAction, token: String, args: [String]) async throws {
        guard inFlightActions[token] == nil else { return }
        inFlightActions[token] = action
        actionErrors[token] = nil
        let startedAt = Date.now
        defer {
            inFlightActions[token] = nil
            cancellableDownloads.remove(token)
            runningProcesses[token] = nil
        }

        do {
            try await runBrewStreaming(token: token, args: args, cancellable: action == .installing)
            cancelRequested.remove(token)
            await refresh()
        } catch {
            if cancelRequested.contains(token) {
                // User cancelled — not an error. Remove the partial download
                // brew left behind so nothing accumulates in its cache.
                cancelRequested.remove(token)
                Task.detached(priority: .utility) {
                    Self.cleanupIncompleteDownloads(since: startedAt)
                }
                await refresh()
                return
            }
            if let error = error as? LocalHomebrewError {
                actionErrors[token] = error.errorDescription
            } else {
                actionErrors[token] = error.localizedDescription
            }
            throw error
        }
    }

    /// Spawns `brew` attached to a pseudo-terminal and streams its output.
    ///
    /// The stream is watched for the `==> Installing Cask` marker that closes
    /// the safe-to-cancel window. The output tail doubles as stderr for error
    /// reporting.
    private func runBrewStreaming(token: String, args: [String], cancellable: Bool) async throws {
        guard let brewURL = Self.locateBrewBinary() else {
            throw LocalHomebrewError.brewBinaryNotFound
        }

        let process = Process()
        process.executableURL = brewURL
        process.arguments = args
        // pkg-based casks run `sudo installer` internally; with no TTY sudo can't
        // prompt. SUDO_ASKPASS makes brew pass `-A` so sudo asks via our GUI helper.
        if let askpass = Self.ensureAskpassScript(token: token) {
            var environment = ProcessInfo.processInfo.environment
            environment["SUDO_ASKPASS"] = askpass.path
            process.environment = environment
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        runningProcesses[token] = process
        if cancellable { cancellableDownloads.insert(token) }

        let handle = pipe.fileHandleForReading
        let outputTail = await Task.detached(priority: .userInitiated) { () -> String in
            var tail = ""
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { break }  // EOF
                guard let text = String(data: data, encoding: .utf8) else { continue }
                tail = String((tail + text).suffix(2000))

                if text.contains("==> Installing Cask") {
                    // Download finished — cancelling is no longer residual-free.
                    Task { @MainActor in self.cancellableDownloads.remove(token) }
                }
            }
            process.waitUntilExit()
            return tail
        }.value

        if process.terminationStatus != 0 {
            throw LocalHomebrewError.brewCommandFailed(
                args: args,
                exitCode: process.terminationStatus,
                stderr: outputTail.components(separatedBy: "\n").suffix(6).joined(separator: "\n")
            )
        }
    }

    /// Writes the SUDO_ASKPASS helper: re-execs this binary in `--askpass`
    /// mode. Rewritten per mutation so the binary path (moves between dev
    /// builds) and the token stay current.
    private nonisolated static func ensureAskpassScript(token: String) -> URL? {
        guard let executablePath = Bundle.main.executableURL?.path else { return nil }
        // Interpolated into a shell script — keep only known-safe characters.
        let safeToken = token.filter { $0.isLetter || $0.isNumber || "-_+@.".contains($0) }
        let script = """
        #!/bin/sh
        exec "\(executablePath)" --askpass "\(safeToken)"
        """
        let fm = FileManager.default
        guard let base = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("CaskHub", isDirectory: true)
        let url = dir.appendingPathComponent("askpass.sh")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            return nil
        }
        return url
    }

    /// Sends `signal` to a process and all of its descendants (brew forks curl;
    /// signalling only brew would leave curl downloading to a dead parent).
    private nonisolated static func signalTree(pid: Int32, signal: Int32) {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", "\(pid)"]
        let stdout = Pipe()
        pgrep.standardOutput = stdout
        pgrep.standardError = FileHandle.nullDevice
        if (try? pgrep.run()) != nil {
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            pgrep.waitUntilExit()
            let children = String(data: data, encoding: .utf8)?
                .split(whereSeparator: \.isNewline)
                .compactMap { Int32($0) } ?? []
            for child in children {
                signalTree(pid: child, signal: signal)
            }
        }
        kill(pid, signal)
    }

    /// Deletes downloads newer than `cutoff` from Homebrew's cache — the only
    /// residue a download-phase cancel leaves behind. Covers both `*.incomplete`
    /// partials and just-finished archives (cancel can land after the download
    /// completed but before staging began).
    private nonisolated static func cleanupIncompleteDownloads(since cutoff: Date) {
        let fm = FileManager.default
        let cacheURL: URL
        if let override = ProcessInfo.processInfo.environment["HOMEBREW_CACHE"], !override.isEmpty {
            cacheURL = URL(fileURLWithPath: override)
        } else {
            cacheURL = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/Homebrew")
        }
        let downloadsURL = cacheURL.appendingPathComponent("downloads", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            if modified >= cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }

    /// Runs `brew --version` and returns the bare version ("Homebrew 4.6.15" → "4.6.15").
    private nonisolated static func fetchBrewVersion() async -> String? {
        guard let brewURL = locateBrewBinary() else { return nil }
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = brewURL
            process.arguments = ["--version"]
            let stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return nil
            }
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let firstLine = String(data: data, encoding: .utf8)?
                      .split(separator: "\n").first
            else { return nil }
            return firstLine.split(separator: " ").last.map(String.init)
        }.value
    }

    // MARK: - Filesystem Scanning

    /// Scans the Caskroom to build a map of locally-installed casks.
    ///
    /// **Version**: read from the version-directory NAME inside each cask directory
    /// (e.g. `Caskroom/finetune/1.4.1/`), NOT from `INSTALL_RECEIPT.json`'s
    /// `source.version` which freezes at the original install and never updates
    /// after `brew upgrade`.
    ///
    /// **Date**: read from the filesystem modification date of the version directory,
    /// which reflects when Homebrew staged the files for that version.
    ///
    /// **App bundles**: still extracted from the top-level install receipt's
    /// `uninstall_artifacts` — the app name rarely changes between versions.
    private nonisolated static func scanCaskroom(
        fileManager: FileManager
    ) -> Result<[String: LocalCaskInstallation], LocalHomebrewError> {
        guard let caskroomURL = locateCaskroom(fileManager: fileManager) else {
            return .failure(.caskroomNotFound)
        }

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: caskroomURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return .success([:])
        }

        var result: [String: LocalCaskInstallation] = [:]
        for entry in entries {
            var isDir: ObjCBool = false
            guard
                fileManager.fileExists(atPath: entry.path, isDirectory: &isDir),
                isDir.boolValue
            else { continue }

            let token = entry.lastPathComponent

            // 1. Find version directories — non-hidden subdirectories of the cask
            //    directory. `.skipsHiddenFiles` already excludes `.metadata/`.
            guard let subDirs = try? fileManager.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let versionDirs = subDirs.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }

            // Pick the most recently modified version directory.
            guard let versionDir = versionDirs.max(by: { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return dateA < dateB
            }) else { continue }

            let version = versionDir.lastPathComponent
            let installedAt = try? versionDir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

            // 2. Read the receipt for app bundle names only.
            let receiptURL = entry
                .appendingPathComponent(".metadata", isDirectory: true)
                .appendingPathComponent("INSTALL_RECEIPT.json")

            let appBundleNames: [String]
            if let data = try? Data(contentsOf: receiptURL),
               let receipt = try? InstallReceipt(jsonData: data) {
                appBundleNames = receipt.appBundleNames
            } else {
                appBundleNames = []
            }

            result[token] = LocalCaskInstallation(
                token: token,
                installedVersion: version,
                installedAt: installedAt,
                appBundleNames: appBundleNames
            )
        }
        return .success(result)
    }

    // MARK: - Path Discovery

    /// Tries `$HOMEBREW_PREFIX/Caskroom`, then Apple Silicon, then Intel default.
    private nonisolated static func locateCaskroom(fileManager: FileManager) -> URL? {
        var candidates: [URL] = []
        if let prefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], !prefix.isEmpty {
            candidates.append(URL(fileURLWithPath: prefix).appendingPathComponent("Caskroom", isDirectory: true))
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/Caskroom", isDirectory: true))
        candidates.append(URL(fileURLWithPath: "/usr/local/Caskroom", isDirectory: true))
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    /// Tries `$HOMEBREW_PREFIX/bin/brew`, then Apple Silicon, then Intel default.
    private nonisolated static func locateBrewBinary() -> URL? {
        var candidates: [URL] = []
        if let prefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], !prefix.isEmpty {
            candidates.append(URL(fileURLWithPath: prefix).appendingPathComponent("bin/brew"))
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/brew"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/brew"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
