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
struct LocalCaskInstallation: Hashable, Identifiable {
    let token: String
    let installedVersion: String
    let installedAt: Date?
    let appBundleNames: [String]

    var id: String {
        token
    }
}

/// Which background action is currently running for a given cask, if any.
enum CaskAction: Equatable {
    case opening
    case installing
    case updating
    case uninstalling

    var inProgressLabel: String {
        switch self {
        case .opening: return "Opening…"
        case .installing: return "Installing…"
        case .updating: return "Updating…"
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
        case let .appBundleNotFound(token):
            return "Couldn't find an installed app for \(token)."
        case let .brewCommandFailed(args, code, stderr):
            let cmd = (["brew"] + args).joined(separator: " ")
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            // "reports different checksum" = cask; "SHA256 mismatch" = formula dependency.
            if trimmed.contains("reports different checksum") || trimmed.contains("SHA256 mismatch") {
                return "The download doesn't match the checksum Homebrew has on record — "
                    + "the developer likely replaced the release file after it was published. "
                    + "This isn't a problem with your Mac; Homebrew refuses mismatched downloads "
                    + "for security. Try again in a day or two once the cask is updated."
            }
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
    var installedCasks: [String: LocalCaskInstallation] = [:]

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
        case let .success(casks):
            installedCasks = casks
            refreshError = nil
        case let .failure(error):
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

    /// Compares versions with the packaging suffix stripped — cask versions
    /// aren't semver (`125.0,build42` has a build suffix, `125.0_1` a cask
    /// revision), so comparing normalized prefixes avoids flagging an update
    /// when only the packaging changed.
    func isOutdated(token: String, remoteVersion: String) -> Bool {
        guard let installation = installedCasks[token] else { return false }
        return Self.comparableVersion(installation.installedVersion)
            != Self.comparableVersion(remoteVersion)
    }

    private nonisolated static func comparableVersion(_ version: String) -> Substring {
        version.prefix { $0 != "," && $0 != "_" }
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
            Analytics.caskActionCompleted(action, token: token)
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
            Analytics.caskActionFailed(action, token: token)
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
                guard !data.isEmpty else { break } // EOF
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
}
