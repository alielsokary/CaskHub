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
    private(set) var installationSnapshot = InstallationSnapshot.empty {
        didSet { catalogStateRevision &+= 1 }
    }

    @ObservationIgnored var applicationCaskSignatures: [ApplicationCaskSignature] = []
    @ObservationIgnored var installationCatalog = CaskInstallationCatalog.empty

    /// Changes only when state that affects catalog membership or update
    /// eligibility changes; operation progress deliberately does not touch it.
    private(set) var catalogStateRevision = 0

    @ObservationIgnored var packageCaskSignatures: [PackageCaskSignature] = []
    @ObservationIgnored var packageCatalogGeneration = 0

    /// Test seam — the real probe hits TCC via the filesystem.
    @ObservationIgnored var permissionProbe:
        @Sendable (URL?) -> AppManagementPermission.Assessment
        = { AppManagementPermission.assess(target: $0) }

    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let notificationCenter: NotificationCenter

    @ObservationIgnored let operationStore: CaskOperationStore

    @ObservationIgnored var caskDisplayNames: [String: String] = [:]

    @ObservationIgnored let applicationLauncher: any ApplicationLaunching
    @ObservationIgnored let mutationCoordinator: HomebrewMutationCoordinator
    @ObservationIgnored let softwareScanner: any InstalledSoftwareScanning
    @ObservationIgnored let brewBinaryProvider: () -> URL?
    @ObservationIgnored private let caskPlatformProvider: () async -> CaskPlatform?
    @ObservationIgnored private let brewVersionProvider: () async -> String?
    @ObservationIgnored private let homebrewOutdatedProvider: () async -> HomebrewOutdatedReport?
    @ObservationIgnored let tapManager: any HomebrewTapManaging

    var isUpdatingAll: Bool {
        operationStore.isUpdatingAll
    }

    var isUpdatingHomebrew: Bool {
        operationStore.isUpdatingHomebrew
    }

    var hasActiveOperations: Bool {
        operationStore.hasActiveOperations
    }

    private(set) var brewVersion: String?

    private(set) var taps: [HomebrewTap] = [] {
        didSet { if taps != oldValue { catalogStateRevision &+= 1 } }
    }

    private(set) var tapCatalog: [Cask] = []

    private(set) var hasLoadedTaps = false

    private(set) var customBrewPrefix: String?

    /// Homebrew's platform tag, cached between refreshes; nil when detection fails.
    private(set) var caskPlatform: CaskPlatform? {
        didSet { if caskPlatform != oldValue { catalogStateRevision &+= 1 } }
    }

    /// What `brew outdated` lists; nil until Homebrew answers.
    private(set) var homebrewOutdated: HomebrewOutdatedReport? {
        didSet { if homebrewOutdated != oldValue { catalogStateRevision &+= 1 } }
    }

    /// Also offer self-updating casks Homebrew does not list; upgrades then pass `--greedy`.
    private(set) var greedyUpdates: Bool {
        didSet { catalogStateRevision &+= 1 }
    }

    private(set) var zapOnUninstall: Bool

    /// Tokens the user excluded from Adopt Apps, mapped to when they ignored them.
    private(set) var adoptIgnoredDates: [String: Date] {
        didSet { catalogStateRevision &+= 1 }
    }

    let fileManager: FileManager
    private let defaults: UserDefaults
    let applicationDirectories: [URL]

    private static let zapOnUninstallKey = "zapOnUninstall"
    private static let greedyKey = "greedyUpdates"
    private static let adoptIgnoredKey = "adoptIgnoredDates"

    init(
        defaults: UserDefaults = .standard,
        configureDependencies: (inout LocalHomebrewDependencies) -> Void = { _ in }
    ) {
        var dependencies = LocalHomebrewDependencies()
        configureDependencies(&dependencies)
        let operationStore = CaskOperationStore()

        fileManager = dependencies.fileManager
        notificationCenter = dependencies.notificationCenter
        self.defaults = defaults
        applicationDirectories = dependencies.applicationDirectories
            ?? ApplicationDiscovery.defaultDirectories(
                fileManager: dependencies.fileManager
            )
        applicationLauncher = dependencies.applicationLauncher
            ?? WorkspaceApplicationLauncher()
        self.operationStore = operationStore
        mutationCoordinator = HomebrewMutationCoordinator(
            operationStore: operationStore,
            commandExecutor: dependencies.resolvedCommandExecutor(),
            brewBinaryProvider: dependencies.brewBinaryProvider,
            askpassProvider: dependencies.askpassProvider,
            fileManager: dependencies.fileManager,
            lanes: dependencies.laneLimiter ?? .shared
        )
        softwareScanner = dependencies.softwareScanner
            ?? HomebrewInstallationScanner()
        brewBinaryProvider = dependencies.brewBinaryProvider
        brewVersionProvider = dependencies.brewVersionProvider
        let brewBinary = dependencies.brewBinaryProvider
        caskPlatformProvider = dependencies.caskPlatformProvider
            ?? { await HomebrewPlatformLoader().load(from: brewBinary()) }
        homebrewOutdatedProvider = dependencies.homebrewOutdatedProvider
            ?? { await HomebrewOutdatedLoader().load(from: brewBinary()) }
        tapManager = dependencies.tapManager ?? HomebrewTapLoader()
        zapOnUninstall = defaults.bool(forKey: Self.zapOnUninstallKey)
        greedyUpdates = defaults.bool(forKey: Self.greedyKey)
        adoptIgnoredDates = defaults.dictionary(forKey: Self.adoptIgnoredKey) as? [String: Date] ?? [:]
        customBrewPrefix = defaults.string(forKey: HomebrewLocator.customPrefixKey)
        observeApplicationActivation()
    }

    private func observeApplicationActivation() {
        // The permission-request alert tells the user to grant App Management and
        // come back — returning to the app is the cue to finish those adoptions.
        activationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.operationStore.pendingPermissions.isEmpty {
                    await self.refresh()
                    await self.resumePendingAdoptions()
                } else if self.brewVersion == nil {
                    await self.refresh()
                }
            }
        }
    }

    deinit {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
    }

    func setZapOnUninstall(_ enabled: Bool) {
        zapOnUninstall = enabled
        defaults.set(enabled, forKey: Self.zapOnUninstallKey)
    }

    func setGreedyUpdates(_ enabled: Bool) {
        greedyUpdates = enabled
        defaults.set(enabled, forKey: Self.greedyKey)
    }

    func setAdoptIgnored(_ token: String, _ ignored: Bool) {
        if ignored {
            adoptIgnoredDates[token] = .now
        } else {
            adoptIgnoredDates.removeValue(forKey: token)
        }
        defaults.set(adoptIgnoredDates, forKey: Self.adoptIgnoredKey)
    }

    func commitInstallationSnapshot(_ snapshot: InstallationSnapshot) {
        installationSnapshot = snapshot
    }

    func setCustomBrewPrefix(_ prefix: String?) async {
        customBrewPrefix = prefix
        if let prefix, !prefix.isEmpty {
            defaults.set(prefix, forKey: HomebrewLocator.customPrefixKey)
        } else {
            defaults.removeObject(forKey: HomebrewLocator.customPrefixKey)
        }
        invalidateBrewVersion()
        await refresh()
    }

    func invalidateBrewVersion() {
        brewVersion = nil
        caskPlatform = nil
    }

    func refreshHomebrewOutdated() async {
        homebrewOutdated = await homebrewOutdatedProvider()
    }

    func refreshTaps() async {
        guard let snapshot = await tapManager.load(from: brewBinaryProvider()) else {
            hasLoadedTaps = true
            return
        }
        tapCatalog = snapshot.casks
        taps = snapshot.taps
        hasLoadedTaps = true
    }

    func updateTaps() async -> HomebrewTapCommandResult {
        let result = await tapManager.update(using: brewBinaryProvider())
        async let taps: Void = refreshTaps()
        async let outdated: Void = refreshHomebrewOutdated()
        async let installed: Void = refresh()
        _ = await (taps, outdated, installed)
        return result
    }

    func addTap(_ name: String, remote: String?) async -> HomebrewTapCommandResult {
        let result = await tapManager.add(name, remote: remote, using: brewBinaryProvider())
        if result.succeeded { await refreshTaps() }
        return result
    }

    func removeTap(_ name: String) async -> HomebrewTapCommandResult {
        let result = await tapManager.remove(name, using: brewBinaryProvider())
        if result.succeeded { await refreshTaps() }
        return result
    }

    // MARK: - Detection

    func refresh() async {
        let prefix = customBrewPrefix
        let platform = await caskPlatformProvider()
        guard prefix == customBrewPrefix else { return }
        caskPlatform = platform
        if brewVersion == nil {
            brewVersion = await brewVersionProvider()
        }
        while true {
            let request = installedSoftwareScanRequest()
            let packageGeneration = packageCatalogGeneration
            let scanned = await softwareScanner.scan(request)
            guard packageGeneration == packageCatalogGeneration else {
                continue
            }
            commitInstallationSnapshot(scanned)
            CrashReporter.tag(
                "brew.path",
                value: brewBinaryProvider()?.path ?? "not found"
            )
            CrashReporter.tag("brew.version", value: brewVersion ?? "not found")
            CrashReporter.tag("brew.caskroom", value: request.caskroomURL?.path ?? "not found")
            return
        }
    }

    /// Reconciles the catalog identity metadata with the last complete machine
    /// scan, then publishes one replacement snapshot.
    func updatePackageCatalog(_ casks: [Cask]) async {
        applyCatalogRegistration(InstallationCatalogBuilder().build(casks))
        packageCatalogGeneration &+= 1
        let packageGeneration = packageCatalogGeneration
        let request = installedSoftwareScanRequest()

        while packageGeneration == packageCatalogGeneration {
            let baselineRevision = catalogStateRevision
            let current = installationSnapshot
            let reconciled = await softwareScanner.reconcileCatalog(
                request,
                with: current
            )
            guard packageGeneration == packageCatalogGeneration else { return }
            guard baselineRevision == catalogStateRevision else { continue }
            commitInstallationSnapshot(reconciled)
            return
        }
    }

    private func applyCatalogRegistration(
        _ registration: InstallationCatalogRegistration
    ) {
        caskDisplayNames = registration.displayNames
        applicationCaskSignatures = registration.applicationSignatures
        installationCatalog = registration.installationCatalog
        packageCaskSignatures = registration.packageSignatures
    }

}
