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

struct LocalCaskInstallation: Hashable, Identifiable {
    let token: String
    let installedVersion: String
    let installedAt: Date?
    let appBundleNames: [String]

    /// Brew still lists this cask, but its app was removed outside Homebrew
    /// (or its install receipt is gone) — opens and upgrades are doomed.
    let isZombie: Bool

    init(
        token: String,
        installedVersion: String,
        installedAt: Date?,
        appBundleNames: [String],
        isZombie: Bool = false
    ) {
        self.token = token
        self.installedVersion = installedVersion
        self.installedAt = installedAt
        self.appBundleNames = appBundleNames
        self.isZombie = isZombie
    }

    var id: String {
        token
    }
}

enum CaskAction: Equatable {
    case opening
    case installing
    case adopting
    case updating
    case uninstalling
    case queued

    var inProgressLabel: String {
        switch self {
        case .opening: return "Opening…"
        case .installing: return "Installing…"
        case .adopting: return "Adopting…"
        case .updating: return "Updating…"
        case .uninstalling: return "Uninstalling…"
        case .queued: return "Queued…"
        }
    }
}

enum LocalHomebrewError: LocalizedError {
    case brewBinaryNotFound
    case appBundleNotFound(token: String)
    case brewCommandFailed(args: [String], exitCode: Int32, stderr: String)

    /// Machine states (no Homebrew installed), not bugs — never worth a Sentry event.
    var isEnvironmental: Bool {
        if case .brewBinaryNotFound = self { return true }
        return false
    }

    /// Coarse classes for Sentry grouping — one issue per way brew fails, not per cask.
    static func failureClass(stderr: String) -> String {
        if isStrandedApp(stderr: stderr) { return "stranded-caskroom-app" }
        if stderr.contains("is not there") { return "missing-artifact-source" }
        if stderr.contains("different from the one being installed") { return "adopt-version-mismatch" }
        if stderr.contains("Operation not permitted") { return "permission-denied" }
        if stderr.contains("No Cask with this name exists") || stderr.contains("No casks found") {
            return "unknown-cask"
        }
        if stderr.contains("is not installed") { return "not-installed" }
        if stderr.contains("reports different checksum") || stderr.contains("SHA256 mismatch") {
            return "checksum-mismatch"
        }
        if stderr.contains("already an App at") { return "app-conflict" }
        return "uncategorized"
    }

    /// A previous interrupted operation parked the real .app inside the Caskroom
    /// version directory; every upgrade then fails until the copy is cleared.
    static func isStrandedApp(stderr: String) -> Bool {
        stderr.contains("already an App at") && stderr.contains("Caskroom")
    }

    var errorDescription: String? {
        switch self {
        case .brewBinaryNotFound:
            return "Couldn't locate the brew binary. Is Homebrew installed?"
        case let .appBundleNotFound(token):
            return "Couldn't find an installed app for \(token)."
        case let .brewCommandFailed(args, code, stderr):
            let cmd = (["brew"] + args).joined(separator: " ")
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isAppManagementDenial(stderr: trimmed) {
                return "macOS blocked CaskHub from modifying apps on your Mac. "
                    + "Enable CaskHub under System Settings → Privacy & Security → "
                    + "App Management, then try again."
            }
            if Self.isStrandedApp(stderr: trimmed) {
                return "A previous update left an old copy of the app inside Homebrew's "
                    + "records, and Homebrew refuses every upgrade until it's cleared. "
                    + "Repair removes the leftover copy and reinstalls the app fresh — "
                    + "your settings and data are kept."
            }
            if Self.isAdoptMismatch(args: args, stderr: trimmed) {
                return "Your installed copy doesn't match the version Homebrew has on record, "
                    + "so it can't be adopted as-is. You can replace it with Homebrew's copy "
                    + "instead — your settings and data are kept."
            }
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

    /// The App Management (TCC) permission gating modification of other apps' bundles.
    static func isAppManagementDenial(stderr: String) -> Bool {
        stderr.contains("Operation not permitted")
    }

    /// `brew install --adopt` refuses when the on-disk app differs from the cask's version.
    static func isAdoptMismatch(args: [String], stderr: String) -> Bool {
        args.contains("--adopt")
            && (stderr.contains("different from the one being installed")
                || stderr.contains("already an App at"))
    }
}

// MARK: - LocalHomebrewService

@MainActor
@Observable
final class LocalHomebrewService {
    var installedCasks: [String: LocalCaskInstallation] = [:]

    /// Non-Mac-App-Store bundle names found in /Applications and ~/Applications.
    var externalAppNames: Set<String> = []

    /// Executable names found in common install locations (~/.local/bin, /usr/local/bin, …).
    var externalBinaryNames: Set<String> = []

    private(set) var adoptReplaceOffers: Set<String> = []

    /// Casks wedged by a stranded app copy inside the Caskroom; repair =
    /// clear brew's records, then reinstall fresh.
    private(set) var repairOffers: Set<String> = []

    private(set) var appManagementDenials: Set<String> = []

    /// Adoptions waiting for the App Management permission; value = retry with `--force`.
    private(set) var permissionRequests: [String: Bool] = [:]

    /// Test seam — the real probe hits TCC via the filesystem.
    @ObservationIgnored var permissionProbe: @Sendable () -> AppManagementPermission.Status
        = { AppManagementPermission.probe() }

    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    private(set) var inFlightActions: [String: CaskAction] = [:]

    private(set) var cancellableDownloads: Set<String> = []

    private(set) var cancelRequested: Set<String> = []

    @ObservationIgnored private var runningProcesses: [String: Process] = [:]

    private(set) var actionErrors: [String: String] = [:]

    private(set) var isUpdatingAll = false

    private(set) var lastRefresh: Date?

    private(set) var brewVersion: String?

    private(set) var customBrewPrefix: String?

    /// Include self-updating casks (`auto_updates: true`) in updates, via `brew upgrade --greedy`.
    private(set) var greedyUpdates: Bool

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let applicationDirectories: [URL]

    private static let greedyKey = "greedyUpdates"

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        applicationDirectories: [URL]? = nil
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.applicationDirectories = applicationDirectories
            ?? Self.defaultApplicationDirectories(fileManager)
        greedyUpdates = defaults.bool(forKey: Self.greedyKey)
        customBrewPrefix = defaults.string(forKey: Self.customBrewPrefixKey)

        // The permission-request alert tells the user to grant App Management and
        // come back — returning to the app is the cue to finish those adoptions.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.resumePendingAdoptions()
                if self.brewVersion == nil {
                    await self.refresh()
                }
            }
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func setGreedyUpdates(_ enabled: Bool) {
        greedyUpdates = enabled
        defaults.set(enabled, forKey: Self.greedyKey)
    }

    func setCustomBrewPrefix(_ prefix: String?) async {
        customBrewPrefix = prefix
        if let prefix, !prefix.isEmpty {
            defaults.set(prefix, forKey: Self.customBrewPrefixKey)
        } else {
            defaults.removeObject(forKey: Self.customBrewPrefixKey)
        }
        brewVersion = nil
        await refresh()
    }

    // MARK: - Detection

    func refresh() async {
        let fm = fileManager
        if brewVersion == nil {
            brewVersion = await Self.fetchBrewVersion()
        }
        let appDirs = applicationDirectories
        let (casks, appNames, binaryNames) = await Task.detached(priority: .userInitiated) {
            (
                Self.scanCaskroom(fileManager: fm, applicationDirectories: appDirs),
                Self.scanApplications(fileManager: fm),
                Self.scanBinaryDirectories(fileManager: fm)
            )
        }.value
        externalAppNames = appNames
        externalBinaryNames = binaryNames

        CrashReporter.tag("brew.path", value: Self.locateBrewBinary()?.path ?? "not found")
        CrashReporter.tag("brew.caskroom", value: Self.locateCaskroom(fileManager: fm)?.path ?? "not found")

        installedCasks = casks
        lastRefresh = .now
    }

    func isInstalled(token: String) -> Bool {
        installedCasks[token] != nil
    }

    /// The cask isn't brew-managed, but its app already sits in /Applications.
    func isAdoptable(_ cask: Cask) -> Bool {
        installedCasks[cask.token] == nil
            && cask.appArtifactNames.contains(where: externalAppNames.contains)
    }

    /// A CLI cask whose tool is on the device via some other installer
    /// (e.g. claude-code's native install script). Detected, not managed.
    func isExternalCLI(_ cask: Cask) -> Bool {
        installedCasks[cask.token] == nil
            && cask.binaryArtifactNames.contains(where: externalBinaryNames.contains)
    }

    func clearError(for token: String) {
        actionErrors[token] = nil
        adoptReplaceOffers.remove(token)
        repairOffers.remove(token)
        appManagementDenials.remove(token)
    }

    func isOutdated(token: String, remoteVersion: String) -> Bool {
        guard let installation = installedCasks[token], !installation.isZombie else { return false }
        return Self.comparableVersion(installation.installedVersion)
            != Self.comparableVersion(remoteVersion)
    }

    private nonisolated static func comparableVersion(_ version: String) -> Substring {
        version.prefix { $0 != "," && $0 != "_" }
    }

    func hasAvailableUpdate(token: String, remoteVersion: String, autoUpdates: Bool?) -> Bool {
        (greedyUpdates || autoUpdates != true) && isOutdated(token: token, remoteVersion: remoteVersion)
    }

    // MARK: - Actions

    /// The scan's zombie verdict cross-checked against the *current* cask
    /// artifacts: auto-updating apps can rename their bundle on disk
    /// (Codex.app → ChatGPT.app), stranding the install-time receipt and
    /// symlink while the app lives on under its new name. Deletion is only
    /// offered when the apps the cask declares today are verifiably gone too.
    func isZombie(_ cask: Cask) -> Bool {
        guard let installation = installedCasks[cask.token], installation.isZombie,
              !cask.appArtifactNames.isEmpty
        else { return false }
        return existingBundleURL(named: cask.appArtifactNames) == nil
    }

    /// Opens via the receipt's bundle names, falling back to the cask's current
    /// artifact names — receipts go stale when apps rename themselves.
    func open(_ cask: Cask) {
        actionErrors[cask.token] = nil
        let receiptNames = installedCasks[cask.token]?.appBundleNames ?? []
        openBundle(named: receiptNames + cask.appArtifactNames, token: cask.token)
    }

    func openApp(token: String) {
        actionErrors[token] = nil

        guard let installation = installedCasks[token] else {
            actionErrors[token] = LocalHomebrewError.appBundleNotFound(token: token).errorDescription
            return
        }
        openBundle(named: installation.appBundleNames, token: token)
    }

    /// Launches a not-yet-adopted app straight from its on-disk bundle.
    func openExternalApp(cask: Cask) {
        actionErrors[cask.token] = nil
        openBundle(named: cask.appArtifactNames, token: cask.token)
    }

    /// Version of a not-yet-adopted app, read from its bundle's Info.plist.
    func externalAppVersion(for cask: Cask) -> String? {
        guard installedCasks[cask.token] == nil,
              let appURL = existingBundleURL(named: cask.appArtifactNames),
              let info = Bundle(url: appURL)?.infoDictionary
        else { return nil }
        return info["CFBundleShortVersionString"] as? String
            ?? info["CFBundleVersion"] as? String
    }

    private func openBundle(named names: [String], token: String) {
        guard let appURL = existingBundleURL(named: names) else {
            actionErrors[token] = LocalHomebrewError.appBundleNotFound(token: token).errorDescription
            return
        }

        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    private func existingBundleURL(named names: [String]) -> URL? {
        names.flatMap { name in
            applicationDirectories.map { $0.appendingPathComponent(name) }
        }
        .first { fileManager.fileExists(atPath: $0.path) }
    }

    func install(token: String) async throws {
        try await runMutation(.installing, token: token, args: ["install", "--cask", token])
    }

    func uninstall(token: String) async throws {
        try await runMutation(.uninstalling, token: token, args: ["uninstall", "--cask", token])
    }

    /// Clears a zombie Caskroom entry — the app is already gone, `--force`
    /// removes the leftover brew bookkeeping without complaining about it.
    func repair(token: String) async throws {
        try await runMutation(
            .uninstalling, token: token, args: ["uninstall", "--cask", token, "--force"]
        )
    }

    /// A stranded copy inside the Caskroom wedges every upgrade: clear brew's
    /// records (`--force` tolerates the mess), then install fresh. Settings
    /// and user data live outside the bundle and survive.
    func repairReinstalling(token: String) async throws {
        repairOffers.remove(token)
        try await runMutation(
            .uninstalling, token: token, args: ["uninstall", "--cask", token, "--force"]
        )
        try await runMutation(.installing, token: token, args: ["install", "--cask", token])
    }

    func upgrade(token: String) async throws {
        let args = ["upgrade", "--cask", token] + (greedyUpdates ? ["--greedy"] : [])
        try await runMutation(.updating, token: token, args: args)
    }

    func updateAll(tokens: [String]) async {
        guard !isUpdatingAll else { return }
        isUpdatingAll = true
        defer { isUpdatingAll = false }
        for token in tokens where inFlightActions[token] == nil {
            inFlightActions[token] = .queued
        }
        for token in tokens {
            try? await upgrade(token: token)
        }
    }

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

    /// Classifies a brew failure into the offer sets the alert UI reads.
    func noteFailure(token: String, error: Error) {
        guard case let LocalHomebrewError.brewCommandFailed(_, _, stderr) = error else { return }
        if LocalHomebrewError.isAppManagementDenial(stderr: stderr) {
            appManagementDenials.insert(token)
        }
        if LocalHomebrewError.isStrandedApp(stderr: stderr) {
            repairOffers.insert(token)
        }
    }

    private func runMutation(_ action: CaskAction, token: String, args: [String]) async throws {
        guard inFlightActions[token] == nil || inFlightActions[token] == .queued else { return }
        inFlightActions[token] = action
        actionErrors[token] = nil
        let startedAt = Date.now
        defer {
            inFlightActions[token] = nil
            cancellableDownloads.remove(token)
            runningProcesses[token] = nil
        }

        let span = CrashReporter.span(name: args.first ?? "brew", operation: "brew")
        do {
            try await runBrewStreaming(token: token, args: args, cancellable: action == .installing)
            span.finish()
            cancelRequested.remove(token)
            Analytics.caskActionCompleted(action, token: token)
            await refresh()
        } catch {
            if cancelRequested.contains(token) {
                span.finish()
                cancelRequested.remove(token)
                Task.detached(priority: .utility) {
                    Self.cleanupIncompleteDownloads(since: startedAt)
                }
                await refresh()
                return
            }
            span.finish(error: error)
            CrashReporter.capture(error)
            Analytics.caskActionFailed(action, token: token)
            noteFailure(token: token, error: error)
            if let error = error as? LocalHomebrewError {
                actionErrors[token] = error.errorDescription
            } else {
                actionErrors[token] = error.localizedDescription
            }
            throw error
        }
    }

    private func runBrewStreaming(token: String, args: [String], cancellable: Bool) async throws {
        guard let brewURL = Self.locateBrewBinary() else {
            throw LocalHomebrewError.brewBinaryNotFound
        }

        let process = Process()
        process.executableURL = brewURL
        process.arguments = args
        if let askpass = Self.ensureAskpassScript(token: token) {
            var environment = ProcessInfo.processInfo.environment
            environment["SUDO_ASKPASS"] = askpass.path
            process.environment = environment
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let collector = BrewOutputCollector()
        collector.attach(to: process, pipe: pipe) { [weak self] text in
            guard text.contains("==> Installing Cask") else { return }
            Task { @MainActor in self?.cancellableDownloads.remove(token) }
        }

        try process.run()
        runningProcesses[token] = process
        if cancellable { cancellableDownloads.insert(token) }

        let outputTail = await collector.output()

        if process.terminationStatus != 0 {
            throw LocalHomebrewError.brewCommandFailed(
                args: args,
                exitCode: process.terminationStatus,
                stderr: outputTail.components(separatedBy: "\n").suffix(6).joined(separator: "\n")
            )
        }
    }
}

// MARK: - Adoption

extension LocalHomebrewService {
    /// Preflight before `--adopt`: a declared binary missing from the on-disk
    /// bundle makes brew fail *after* it has moved the app aside — and brew's
    /// rollback then deletes the app entirely. Refuse locally and offer the
    /// safe replace path instead.
    func adopt(_ cask: Cask, bypassPermissionCheck: Bool = false) async throws {
        if let missing = adoptBlockedByMissingBinary(cask) {
            adoptReplaceOffers.insert(cask.token)
            actionErrors[cask.token] = "Your installed copy of \(cask.displayName) is missing "
                + "a component Homebrew's version includes (\(missing)), so it can't be "
                + "adopted as-is. You can replace it with Homebrew's copy instead — "
                + "your settings and data are kept."
            return
        }
        try await adopt(token: cask.token, bypassPermissionCheck: bypassPermissionCheck)
    }

    /// Only paths inside the app bundle can be preflighted; staged-path binaries
    /// don't exist until brew downloads the cask, so they're skipped.
    func adoptBlockedByMissingBinary(_ cask: Cask) -> String? {
        guard let appURL = existingBundleURL(named: cask.appArtifactNames) else { return nil }
        let marker = "/\(appURL.lastPathComponent)/"
        for path in cask.binarySourcePaths {
            guard let range = path.range(of: marker) else { continue }
            let resolved = appURL.appendingPathComponent(String(path[range.upperBound...]))
            if !fileManager.fileExists(atPath: resolved.path) {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        }
        return nil
    }

    func adopt(token: String, bypassPermissionCheck: Bool = false) async throws {
        if !bypassPermissionCheck, await !permissionAllowsAdoption() {
            permissionRequests[token] = false
            return
        }
        do {
            try await runMutation(.adopting, token: token, args: ["install", "--cask", token, "--adopt"])
        } catch {
            if case let LocalHomebrewError.brewCommandFailed(args, _, stderr) = error,
               LocalHomebrewError.isAdoptMismatch(args: args, stderr: stderr),
               !LocalHomebrewError.isStrandedApp(stderr: stderr) {
                adoptReplaceOffers.insert(token)
            }
            throw error
        }
    }

    /// Fallback when `--adopt` refuses: replace the on-disk app with Homebrew's copy.
    /// Needs App Management even more than adopt — brew deletes the existing app,
    /// and a TCC-denied delete makes brew escalate to a scary sudo password prompt.
    func adoptReplacing(token: String, bypassPermissionCheck: Bool = false) async throws {
        if !bypassPermissionCheck, await !permissionAllowsAdoption() {
            permissionRequests[token] = true
            return
        }
        adoptReplaceOffers.remove(token)
        try await runMutation(.adopting, token: token, args: ["install", "--cask", token, "--force"])
    }

    func cancelPermissionRequest(token: String) {
        permissionRequests[token] = nil
    }

    /// Called when the app becomes active: if the user granted App Management while
    /// away (in System Settings), finish the adoptions that were waiting on it.
    func resumePendingAdoptions() {
        guard !permissionRequests.isEmpty else { return }
        Task {
            guard await permissionAllowsAdoption() else { return }
            let pending = permissionRequests
            permissionRequests.removeAll()
            for (token, useForce) in pending {
                if useForce {
                    try? await adoptReplacing(token: token, bypassPermissionCheck: true)
                } else {
                    try? await adopt(token: token, bypassPermissionCheck: true)
                }
            }
        }
    }

    /// `.unknown` passes through — only a confirmed denial blocks, so a failed
    /// probe can never lock the user out of adopting.
    private func permissionAllowsAdoption() async -> Bool {
        let probe = permissionProbe
        let status = await Task.detached(priority: .userInitiated) { probe() }.value
        return status != .denied
    }
}
