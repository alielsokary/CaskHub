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

    @ObservationIgnored var fullDiskAccessProbe: @Sendable () -> FullDiskAccessPermission.Status
        = { FullDiskAccessPermission.probe() }

    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let notificationCenter: NotificationCenter

    @ObservationIgnored let operationStore: CaskOperationStore

    @ObservationIgnored var caskDisplayNames: [String: String] = [:]

    @ObservationIgnored let applicationLauncher: any ApplicationLaunching
    @ObservationIgnored let mutationCoordinator: HomebrewMutationCoordinator
    @ObservationIgnored let pinCommands: HomebrewPinCommands
    var pinChangesInFlight: Set<String> = []
    var pinFailureMessage: String?
    @ObservationIgnored let softwareScanner: any InstalledSoftwareScanning
    @ObservationIgnored let brewBinaryProvider: () -> URL?
    @ObservationIgnored private let caskPlatformProvider: () async -> CaskPlatform?
    @ObservationIgnored private let brewVersionProvider: () async -> String?
    @ObservationIgnored private let homebrewOutdatedProvider: () async -> HomebrewOutdatedReport?
    @ObservationIgnored let tapIndexProvider: () async -> TapIndex?
    @ObservationIgnored let installedFormulaeProvider: (String) async -> [String]
    @ObservationIgnored let tapUpdateProvider: () async -> Void
    @ObservationIgnored let tapTrustProvider: () async -> TapTrust

    /// Third-party taps; replaced only by a complete, successful load.
    var tapIndex = TapIndex.empty
    /// A first install from a tap waiting for the user's trust confirmation.
    var pendingTrustInstall: Cask?
    @ObservationIgnored var cancelledTapAdds: Set<String> = []
    @ObservationIgnored let lanes: HomebrewLaneLimiter

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

    /// Where new casks install; nil keeps Homebrew's default `/Applications`.
    private(set) var applicationDirectoryOverride: URL?

    /// Tokens the user excluded from Adopt Apps, mapped to when they ignored them.
    private(set) var adoptIgnoredDates: [String: Date] {
        didSet { catalogStateRevision &+= 1 }
    }

    /// References of the casks the user saved to come back to; independent of install state.
    private(set) var savedReferences: Set<String>

    let fileManager: FileManager
    let defaults: UserDefaults
    private let baseApplicationDirectories: [URL]

    var applicationDirectories: [URL] {
        guard let applicationDirectoryOverride,
              !baseApplicationDirectories.map(\.path).contains(applicationDirectoryOverride.path)
        else { return baseApplicationDirectories }
        return baseApplicationDirectories + [applicationDirectoryOverride]
    }

    private static let zapOnUninstallKey = "zapOnUninstall"
    private static let greedyKey = "greedyUpdates"
    private static let adoptIgnoredKey = "adoptIgnoredDates"
    private static let savedKey = "savedCaskReferences"
    private static let applicationDirectoryKey = "caskApplicationDirectory"
    static let defaultApplicationDirectoryPath = "/Applications"

    init(
        defaults: UserDefaults = .standard,
        configureDependencies: (inout LocalHomebrewDependencies) -> Void = { _ in }
    ) {
        var dependencies = LocalHomebrewDependencies()
        configureDependencies(&dependencies)
        let operationStore = CaskOperationStore()
        let lanes = dependencies.laneLimiter ?? .shared
        self.lanes = lanes

        fileManager = dependencies.fileManager
        notificationCenter = dependencies.notificationCenter
        self.defaults = defaults
        baseApplicationDirectories = dependencies.resolvedApplicationDirectories()
        applicationLauncher = dependencies.resolvedApplicationLauncher()
        self.operationStore = operationStore
        let commandExecutor = dependencies.resolvedCommandExecutor()
        mutationCoordinator = HomebrewMutationCoordinator(
            operationStore: operationStore,
            commandExecutor: commandExecutor,
            brewBinaryProvider: dependencies.brewBinaryProvider,
            askpassProvider: dependencies.askpassProvider,
            fileManager: dependencies.fileManager,
            lanes: lanes,
            fetchStallTimeout: dependencies.fetchStallTimeout,
            lockWait: BrewLockWait(
                interval: dependencies.brewLockRetryInterval,
                limit: dependencies.brewLockWaitLimit,
                operationStore: operationStore
            )
        )
        pinCommands = HomebrewPinCommands(
            commandExecutor: commandExecutor,
            brewBinaryProvider: dependencies.brewBinaryProvider
        )
        softwareScanner = dependencies.resolvedSoftwareScanner()
        brewBinaryProvider = dependencies.brewBinaryProvider
        brewVersionProvider = dependencies.brewVersionProvider
        caskPlatformProvider = dependencies.resolvedCaskPlatformProvider()
        homebrewOutdatedProvider = dependencies.resolvedHomebrewOutdatedProvider()
        tapIndexProvider = dependencies.resolvedTapIndexProvider()
        installedFormulaeProvider = dependencies.resolvedInstalledFormulaeProvider()
        tapTrustProvider = dependencies.resolvedTapTrustProvider()
        tapUpdateProvider = dependencies.resolvedTapUpdateProvider()
        zapOnUninstall = defaults.bool(forKey: Self.zapOnUninstallKey)
        greedyUpdates = defaults.bool(forKey: Self.greedyKey)
        adoptIgnoredDates = defaults.dictionary(forKey: Self.adoptIgnoredKey) as? [String: Date] ?? [:]
        savedReferences = Set(defaults.stringArray(forKey: Self.savedKey) ?? [])
        customBrewPrefix = defaults.string(forKey: HomebrewLocator.customPrefixKey)
        applicationDirectoryOverride = defaults.string(forKey: Self.applicationDirectoryKey)
            .map { URL(fileURLWithPath: $0) }
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

    func setApplicationDirectory(_ directory: URL?) async {
        let path = directory?.standardizedFileURL.path
        applicationDirectoryOverride = path.flatMap {
            $0 == Self.defaultApplicationDirectoryPath ? nil : URL(fileURLWithPath: $0)
        }
        if let applicationDirectoryOverride {
            defaults.set(applicationDirectoryOverride.path, forKey: Self.applicationDirectoryKey)
        } else {
            defaults.removeObject(forKey: Self.applicationDirectoryKey)
        }
        await refresh()
    }

    func setAdoptIgnored(_ token: String, _ ignored: Bool) {
        if ignored {
            adoptIgnoredDates[token] = .now
        } else {
            adoptIgnoredDates.removeValue(forKey: token)
        }
        defaults.set(adoptIgnoredDates, forKey: Self.adoptIgnoredKey)
    }

    func setSaved(_ reference: String, _ saved: Bool) {
        if saved {
            savedReferences.insert(reference)
        } else {
            savedReferences.remove(reference)
        }
        defaults.set(savedReferences.sorted(), forKey: Self.savedKey)
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
