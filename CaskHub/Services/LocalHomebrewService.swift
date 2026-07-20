//
//  LocalHomebrewService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/04/2026.
//

import AppKit
import Foundation
import Observation

// MARK: - LocalHomebrewService

@MainActor
@Observable
final class LocalHomebrewService {
    var installedCasks: [String: LocalCaskInstallation] = [:]

    /// Non-Mac-App-Store bundle names found in /Applications and ~/Applications.
    var externalAppNames: Set<String> = []

    /// Mac App Store bundles that must be shown as installed but never adopted.
    var macAppStoreAppNames: Set<String> = []

    /// Executable names found in common install locations (~/.local/bin, /usr/local/bin, …).
    var externalBinaryNames: Set<String> = []

    var adoptReplaceOffers: Set<String> = []

    /// Casks wedged by a stranded app copy inside the Caskroom; repair =
    /// clear brew's records, then reinstall fresh.
    var repairOffers: Set<String> = []

    var appManagementDenials: Set<String> = []

    /// Adoptions waiting for the App Management permission; value = retry with `--force`.
    var permissionRequests: [String: Bool] = [:]

    /// Test seam — the real probe hits TCC via the filesystem.
    @ObservationIgnored var permissionProbe: @Sendable () -> AppManagementPermission.Status
        = { AppManagementPermission.probe() }

    /// Test seam — launching a real bundle from unit tests raises Finder's
    /// "file can't be found" dialog on fixture apps.
    @ObservationIgnored var appLauncher: (URL) -> Void = { url in
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    private(set) var inFlightActions: [String: CaskAction] = [:]

    private(set) var cancellableDownloads: Set<String> = []

    private(set) var cancelRequested: Set<String> = []

    @ObservationIgnored private var runningProcesses: [String: Process] = [:]

    @ObservationIgnored private let processRunner: any BrewProcessRunning
    @ObservationIgnored private let brewBinaryProvider: () -> URL?
    @ObservationIgnored private let brewVersionProvider: () async -> String?

    var actionErrors: [String: String] = [:]

    private(set) var isUpdatingAll = false

    private(set) var lastRefresh: Date?

    private(set) var brewVersion: String?

    private(set) var customBrewPrefix: String?

    /// Include self-updating casks (`auto_updates: true`) in updates, via `brew upgrade --greedy`.
    private(set) var greedyUpdates: Bool

    let fileManager: FileManager
    private let defaults: UserDefaults
    let applicationDirectories: [URL]

    private static let greedyKey = "greedyUpdates"

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        applicationDirectories: [URL]? = nil,
        processRunner: (any BrewProcessRunning)? = nil,
        brewBinaryProvider: @escaping () -> URL? = { LocalHomebrewService.locateBrewBinary() },
        brewVersionProvider: @escaping () async -> String? = { await LocalHomebrewService.fetchBrewVersion() }
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.applicationDirectories = applicationDirectories
            ?? Self.defaultApplicationDirectories(fileManager)
        self.processRunner = processRunner ?? SystemBrewProcessRunner()
        self.brewBinaryProvider = brewBinaryProvider
        self.brewVersionProvider = brewVersionProvider
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
            brewVersion = await brewVersionProvider()
        }
        let appDirs = applicationDirectories
        let (casks, applications, binaryNames) = await Task.detached(priority: .userInitiated) {
            (
                Self.scanCaskroom(fileManager: fm, applicationDirectories: appDirs),
                Self.scanApplications(fileManager: fm),
                Self.scanBinaryDirectories(fileManager: fm)
            )
        }.value
        externalAppNames = applications.adoptableNames
        macAppStoreAppNames = applications.macAppStoreNames
        externalBinaryNames = binaryNames

        CrashReporter.tag("brew.path", value: Self.locateBrewBinary()?.path ?? "not found")
        CrashReporter.tag("brew.caskroom", value: Self.locateCaskroom(fileManager: fm)?.path ?? "not found")

        installedCasks = casks
        lastRefresh = .now
    }

    // MARK: - Actions

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
    /// The download comes FIRST: a failed fetch after the uninstall would
    /// leave the user with no app at all, and `brew fetch` exits non-zero on
    /// download failure, so it's a reliable gate.
    func repairReinstalling(token: String) async throws {
        guard inFlightActions[token] == nil else { return }
        repairOffers.remove(token)
        inFlightActions[token] = .queued
        do {
            try await runBrewStreaming(token: token, args: ["fetch", "--cask", token], cancellable: false)
            inFlightActions[token] = nil
            runningProcesses[token] = nil
        } catch {
            inFlightActions[token] = nil
            runningProcesses[token] = nil
            CrashReporter.capture(error)
            actionErrors[token] = (error as? LocalHomebrewError)?.errorDescription
                ?? error.localizedDescription
            throw error
        }
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
    /// Stranded detection also consults the filesystem — brew can reword its
    /// errors, but a real .app parked in the Caskroom can't be misread.
    func noteFailure(token: String, error: Error) {
        guard case let LocalHomebrewError.brewCommandFailed(args, _, stderr) = error else { return }
        if LocalHomebrewError.isAppManagementDenial(stderr: stderr) {
            appManagementDenials.insert(token)
        }
        if LocalHomebrewError.isStrandedApp(stderr: stderr)
            || (args.first == "upgrade" && hasStrandedCopy(token: token)) {
            repairOffers.insert(token)
        }
    }

    private func hasStrandedCopy(token: String) -> Bool {
        guard let caskroom = Self.locateCaskroom(fileManager: fileManager) else { return false }
        return Self.strandedCopyExists(in: caskroom, token: token, fileManager: fileManager)
    }

    func runMutation(_ action: CaskAction, token: String, args: [String]) async throws {
        guard inFlightActions[token] == nil || inFlightActions[token] == .queued else { return }
        inFlightActions[token] = action
        actionErrors[token] = nil
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
                // Homebrew owns its cache and safely resumes partial downloads.
                // Never sweep the shared cache: another brew process may be using it.
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
        guard let brewURL = brewBinaryProvider() else {
            throw LocalHomebrewError.brewBinaryNotFound
        }

        let askpass = Self.ensureAskpassScript(token: token)
        defer {
            if let askpass { Self.removeAskpassScript(at: askpass) }
        }

        var environment = ProcessInfo.processInfo.environment
        if let askpass {
            environment["SUDO_ASKPASS"] = askpass.path
        }

        let result = try await processRunner.run(
            executableURL: brewURL,
            arguments: args,
            environment: environment,
            onStart: { [weak self] process in
                self?.runningProcesses[token] = process
                if cancellable { self?.cancellableDownloads.insert(token) }
            },
            onChunk: { [weak self] text in
                guard text.contains("==> Installing Cask") else { return }
                guard let self else { return }
                Task { @MainActor in self.cancellableDownloads.remove(token) }
            }
        )

        if result.exitCode != 0 {
            throw LocalHomebrewError.brewCommandFailed(
                args: args,
                exitCode: result.exitCode,
                stderr: result.output.components(separatedBy: "\n").suffix(6).joined(separator: "\n")
            )
        }
    }
}
