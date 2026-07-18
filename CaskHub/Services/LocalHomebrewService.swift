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
            if Self.isAppManagementDenial(stderr: trimmed) {
                return "macOS blocked CaskHub from modifying apps on your Mac. "
                    + "Enable CaskHub under System Settings → Privacy & Security → "
                    + "App Management, then try again."
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

    private(set) var adoptReplaceOffers: Set<String> = []

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

    private(set) var refreshError: LocalHomebrewError?

    private(set) var brewVersion: String?

    /// Include self-updating casks (`auto_updates: true`) in updates, via `brew upgrade --greedy`.
    private(set) var greedyUpdates: Bool

    private let fileManager: FileManager
    private let defaults: UserDefaults

    private static let greedyKey = "greedyUpdates"

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
        greedyUpdates = defaults.bool(forKey: Self.greedyKey)

        // The permission-request alert tells the user to grant App Management and
        // come back — returning to the app is the cue to finish those adoptions.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumePendingAdoptions() }
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

    // MARK: - Detection

    func refresh() async {
        let fm = fileManager
        if brewVersion == nil {
            brewVersion = await Self.fetchBrewVersion()
        }
        let (result, appNames) = await Task.detached(priority: .userInitiated) {
            (Self.scanCaskroom(fileManager: fm), Self.scanApplications(fileManager: fm))
        }.value
        externalAppNames = appNames

        switch result {
        case let .success(casks):
            installedCasks = casks
            refreshError = nil
        case let .failure(error):
            refreshError = error
            CrashReporter.capture(error)
        }
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

    func clearError(for token: String) {
        actionErrors[token] = nil
        adoptReplaceOffers.remove(token)
        appManagementDenials.remove(token)
    }

    func isOutdated(token: String, remoteVersion: String) -> Bool {
        guard let installation = installedCasks[token] else { return false }
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
        names.flatMap { name -> [URL] in
            [
                URL(fileURLWithPath: "/Applications").appendingPathComponent(name),
                fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent("Applications")
                    .appendingPathComponent(name)
            ]
        }
        .first { fileManager.fileExists(atPath: $0.path) }
    }

    func install(token: String) async throws {
        try await runMutation(.installing, token: token, args: ["install", "--cask", token])
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
               LocalHomebrewError.isAdoptMismatch(args: args, stderr: stderr) {
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

    func uninstall(token: String) async throws {
        try await runMutation(.uninstalling, token: token, args: ["uninstall", "--cask", token])
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
            if let error = error as? LocalHomebrewError {
                if case let .brewCommandFailed(_, _, stderr) = error,
                   LocalHomebrewError.isAppManagementDenial(stderr: stderr) {
                    appManagementDenials.insert(token)
                }
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
