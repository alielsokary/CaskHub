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

    @ObservationIgnored let operationStore: CaskOperationStore

    @ObservationIgnored var caskDisplayNames: [String: String] = [:]
    @ObservationIgnored var brewOutputBuffers: [String: String] = [:]
    @ObservationIgnored var lastProgressUpdates: [String: Date] = [:]

    @ObservationIgnored let commandExecutor: any HomebrewCommandExecuting
    @ObservationIgnored let softwareScanner: any InstalledSoftwareScanning
    @ObservationIgnored let brewBinaryProvider: () -> URL?
    @ObservationIgnored private let brewVersionProvider: () async -> String?

    private(set) var isUpdatingAll = false

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
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        applicationDirectories: [URL]? = nil,
        processRunner: (any BrewProcessRunning)? = nil,
        commandExecutor: (any HomebrewCommandExecuting)? = nil,
        operationStore: CaskOperationStore? = nil,
        softwareScanner: (any InstalledSoftwareScanning)? = nil,
        brewBinaryProvider: @escaping () -> URL? = {
            HomebrewLocator.brewBinaryURL()
        },
        brewVersionProvider: @escaping () async -> String? = {
            await HomebrewVersionLoader().load(
                from: HomebrewLocator.brewBinaryURL()
            )
        }
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.applicationDirectories = applicationDirectories
            ?? ApplicationDiscovery.defaultDirectories(fileManager: fileManager)
        self.commandExecutor = commandExecutor ?? SystemHomebrewCommandExecutor(
            processRunner: processRunner ?? SystemBrewProcessRunner()
        )
        self.operationStore = operationStore ?? CaskOperationStore()
        self.softwareScanner = softwareScanner ?? HomebrewInstallationScanner()
        self.brewBinaryProvider = brewBinaryProvider
        self.brewVersionProvider = brewVersionProvider
        greedyUpdates = defaults.bool(forKey: Self.greedyKey)
        customBrewPrefix = defaults.string(forKey: HomebrewLocator.customPrefixKey)

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

// MARK: - Actions

extension LocalHomebrewService {
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
        guard operationStore.canBeginOperation(for: token) else { return }
        let caskroomEntry = HomebrewLocator.caskroomURL(
            customPrefix: customBrewPrefix,
            fileManager: fileManager
        )?
            .appendingPathComponent(token)
        let appBundleNames = installedCasks[token]?.appBundleNames ?? []
        Analytics.caskActionStarted(.repairing, token: token, origin: .repair)
        beginOperation(.repairing, token: token)
        defer { clearOperationResources(token: token) }
        do {
            try await runBrewStreaming(token: token, args: ["fetch", "--cask", token], cancellable: false)
            operationStore.send(.clear, for: token)
        } catch {
            CrashReporter.capture(error)
            Analytics.caskActionFailed(.repairing, token: token, origin: .repair)
            noteFailure(token: token, error: error)
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
        defer {
            operationStore.setUpdateAllProgress(nil)
            isUpdatingAll = false
        }
        for token in tokens where operationStore.canBeginOperation(for: token) {
            operationStore.send(.enqueue(.updating), for: token)
        }
        for (index, token) in tokens.enumerated() {
            operationStore.setUpdateAllProgress(CaskUpdateAllProgress(
                currentIndex: index + 1,
                totalCount: tokens.count,
                currentToken: token,
                currentDisplayName: displayName(for: token)
            ))
            try? await upgrade(token: token, origin: .updateAll)
        }
    }

    func cancelInstall(token: String) {
        guard operationStore.state(for: token)?.canCancel == true,
              commandExecutor.cancel(token: token)
        else { return }
        operationStore.send(.requestCancellation, for: token)
    }

    var statusBarOperation: CaskOperationStatus? {
        operationStore.status
    }

    func displayName(for token: String) -> String {
        caskDisplayNames[token] ?? token
    }

}
