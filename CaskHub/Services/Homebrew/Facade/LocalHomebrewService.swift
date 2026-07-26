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
    @ObservationIgnored var permissionProbe: @Sendable () -> AppManagementPermission.Status
        = { AppManagementPermission.probe() }

    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    @ObservationIgnored let operationStore: CaskOperationStore

    @ObservationIgnored var caskDisplayNames: [String: String] = [:]

    @ObservationIgnored let applicationLauncher: any ApplicationLaunching
    @ObservationIgnored let mutationCoordinator: HomebrewMutationCoordinator
    @ObservationIgnored let softwareScanner: any InstalledSoftwareScanning
    @ObservationIgnored let brewBinaryProvider: () -> URL?
    @ObservationIgnored private let brewVersionProvider: () async -> String?

    var isUpdatingAll: Bool {
        operationStore.isUpdatingAll
    }

    private(set) var brewVersion: String?

    private(set) var customBrewPrefix: String?

    /// Include self-updating casks (`auto_updates: true`) in updates, via `brew upgrade --greedy`.
    private(set) var greedyUpdates: Bool {
        didSet { catalogStateRevision &+= 1 }
    }

    let fileManager: FileManager
    private let defaults: UserDefaults
    let applicationDirectories: [URL]

    private static let greedyKey = "greedyUpdates"

    init(
        defaults: UserDefaults = .standard,
        configureDependencies: (inout LocalHomebrewDependencies) -> Void = { _ in }
    ) {
        var dependencies = LocalHomebrewDependencies()
        configureDependencies(&dependencies)
        let operationStore = dependencies.operationStore ?? CaskOperationStore()

        fileManager = dependencies.fileManager
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
            fileManager: dependencies.fileManager
        )
        softwareScanner = dependencies.softwareScanner
            ?? HomebrewInstallationScanner()
        brewBinaryProvider = dependencies.brewBinaryProvider
        brewVersionProvider = dependencies.brewVersionProvider
        greedyUpdates = defaults.bool(forKey: Self.greedyKey)
        customBrewPrefix = defaults.string(forKey: HomebrewLocator.customPrefixKey)
        observeApplicationActivation()
    }

    private func observeApplicationActivation() {
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
        brewVersion = nil
        await refresh()
    }

    // MARK: - Detection

    func refresh() async {
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
