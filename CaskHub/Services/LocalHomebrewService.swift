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

    /// Bundle identifiers disambiguate Store apps that reuse another product's name.
    var macAppStoreBundleIdentifiers: [String: Set<String>] = [:]

    /// Valid app bundles found under the application roots, including nested
    /// bundles such as /Applications/WhatsApp.localized/WhatsApp.app.
    var detectedApplications: [DetectedApplication] = []

    /// Executables found in common install locations (~/.local/bin, /usr/local/bin, …).
    var externalBinaryPaths: [String: URL] = [:]

    /// Package-installed apps matched to cask receipt metadata.
    var externalPackageInstallations: [String: ExternalPackageInstallation] = [:]

    /// Package adoptions awaiting the user's reinstall confirmation.
    var packageAdoptionRequests: Set<String> = []

    @ObservationIgnored var packageCaskSignatures: [PackageCaskSignature] = []
    @ObservationIgnored private var packageCatalogGeneration = 0

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

    var inFlightActions: [String: CaskAction] = [:]

    var cancellableDownloads: Set<String> = []

    var cancelRequested: Set<String> = []

    @ObservationIgnored var runningProcesses: [String: Process] = [:]

    @ObservationIgnored let processRunner: any BrewProcessRunning
    @ObservationIgnored let brewBinaryProvider: () -> URL?
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
        let packageSignatures = packageCaskSignatures
        let packageGeneration = packageCatalogGeneration
        let (casks, applications, binaryPaths, packages) = await Task.detached(priority: .userInitiated) {
            let applications = Self.scanApplications(fileManager: fm, directories: appDirs)
            return (
                Self.scanCaskroom(fileManager: fm, applicationDirectories: appDirs),
                applications,
                Self.scanBinaryDirectories(fileManager: fm),
                Self.scanExternalPackageInstallations(
                    signatures: packageSignatures,
                    availableAppNames: applications.nonStoreNames
                )
            )
        }.value
        externalAppNames = applications.adoptableNames
        macAppStoreAppNames = applications.macAppStoreNames
        macAppStoreBundleIdentifiers = applications.macAppStoreBundleIdentifiers
        detectedApplications = applications.applications
        externalBinaryPaths = binaryPaths
        if packageGeneration == packageCatalogGeneration {
            externalPackageInstallations = packages
        }

        CrashReporter.tag("brew.path", value: Self.locateBrewBinary()?.path ?? "not found")
        CrashReporter.tag("brew.caskroom", value: Self.locateCaskroom(fileManager: fm)?.path ?? "not found")

        installedCasks = casks
        lastRefresh = .now
    }

    /// The catalog provides the package receipt identifiers needed to associate
    /// system package records with Homebrew casks.
    func updatePackageCatalog(_ casks: [Cask]) async {
        packageCaskSignatures = casks.compactMap { cask in
            guard cask.hasPackageArtifact, !cask.packageIdentifiers.isEmpty else { return nil }
            return PackageCaskSignature(
                token: cask.token,
                displayName: cask.displayName,
                receiptPatterns: cask.packageIdentifiers,
                appNameCandidates: cask.packageAppNameCandidates
            )
        }
        packageCatalogGeneration &+= 1
        let packageGeneration = packageCatalogGeneration
        guard !packageCaskSignatures.isEmpty else {
            externalPackageInstallations = [:]
            return
        }

        let signatures = packageCaskSignatures
        let fm = fileManager
        let appDirs = applicationDirectories
        let applications = await Task.detached(priority: .userInitiated) {
            Self.scanApplications(fileManager: fm, directories: appDirs)
        }.value
        externalAppNames = applications.adoptableNames
        macAppStoreAppNames = applications.macAppStoreNames
        macAppStoreBundleIdentifiers = applications.macAppStoreBundleIdentifiers
        detectedApplications = applications.applications
        let packages = await Task.detached(priority: .userInitiated) {
            Self.scanExternalPackageInstallations(
                signatures: signatures,
                availableAppNames: applications.nonStoreNames
            )
        }.value
        if packageGeneration == packageCatalogGeneration {
            externalPackageInstallations = packages
        }
    }

    // MARK: - Actions

    func install(token: String, origin: CaskActionOrigin = .individual) async throws {
        try await runMutation(
            .installing, token: token, args: ["install", "--cask", token], origin: origin
        )
    }

    func uninstall(token: String, origin: CaskActionOrigin = .individual) async throws {
        try await runMutation(
            .uninstalling, token: token, args: ["uninstall", "--cask", token], origin: origin
        )
    }

    /// Clears a zombie Caskroom entry — the app is already gone, `--force`
    /// removes the leftover brew bookkeeping without complaining about it.
    func repair(token: String) async throws {
        try await runMutation(
            .uninstalling,
            token: token,
            args: ["uninstall", "--cask", token, "--force"],
            origin: .repair
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
        let caskroomEntry = Self.locateCaskroom(fileManager: fileManager)?
            .appendingPathComponent(token)
        let appBundleNames = installedCasks[token]?.appBundleNames ?? []
        Analytics.caskActionStarted(.repairing, token: token, origin: .repair)
        inFlightActions[token] = .repairing
        do {
            try await runBrewStreaming(token: token, args: ["fetch", "--cask", token], cancellable: false)
            inFlightActions[token] = nil
            runningProcesses[token] = nil
        } catch {
            inFlightActions[token] = nil
            runningProcesses[token] = nil
            CrashReporter.capture(error)
            Analytics.caskActionFailed(.repairing, token: token, origin: .repair)
            actionErrors[token] = (error as? LocalHomebrewError)?.errorDescription
                ?? error.localizedDescription
            throw error
        }
        do {
            try await runMutation(
                .uninstalling,
                token: token,
                args: ["uninstall", "--cask", token, "--force"],
                origin: .repair,
                environmentOverrides: ["HOMEBREW_NO_AUTOREMOVE": "1"],
                recoverIf: { [self] in
                    repairRemovalSatisfied(
                        caskroomEntry: caskroomEntry,
                        appBundleNames: appBundleNames
                    )
                }
            )
            try await runMutation(
                .installing,
                token: token,
                args: ["install", "--cask", token],
                origin: .repair
            )
            Analytics.caskActionCompleted(.repairing, token: token, origin: .repair)
        } catch {
            Analytics.caskActionFailed(.repairing, token: token, origin: .repair)
            throw error
        }
    }

    func upgrade(token: String, origin: CaskActionOrigin = .individual) async throws {
        let args = ["upgrade", "--cask", token] + (greedyUpdates ? ["--greedy"] : [])
        try await runMutation(.updating, token: token, args: args, origin: origin)
    }

    func updateAll(tokens: [String]) async {
        guard !isUpdatingAll else { return }
        isUpdatingAll = true
        defer { isUpdatingAll = false }
        for token in tokens where inFlightActions[token] == nil {
            inFlightActions[token] = .queued
        }
        for token in tokens {
            try? await upgrade(token: token, origin: .updateAll)
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
}
