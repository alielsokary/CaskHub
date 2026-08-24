//
//  TestFactories.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 19/08/2026.
//

@testable import CaskHub
import Foundation
import Synchronization
import SwiftUI

internal nonisolated func makeDetectedApplication(
    _ bundleName: String,
    id: String? = nil,
    version: String? = nil,
    isMacAppStore: Bool = false,
    inApplicationsDirectory: Bool = true,
    installedAt: Date? = nil,
    url: URL? = nil
) -> DetectedApplication {
    DetectedApplication(
        url: url ?? URL(fileURLWithPath: "/Applications/\(bundleName)"),
        bundleName: bundleName,
        bundleIdentifier: id ?? "com.example.\(bundleName)",
        version: version,
        isMacAppStore: isMacAppStore,
        isDirectlyInApplicationDirectory: inApplicationsDirectory,
        installedAt: installedAt
    )
}

@MainActor
func render(_ view: some View, width: CGFloat = 1100, height: CGFloat = 700) {
    let hosting = NSHostingView(rootView: AnyView(view))
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    hosting.layoutSubtreeIfNeeded()
}

nonisolated struct FixedInstalledSoftwareScanner: InstalledSoftwareScanning {
    let snapshot: InstallationSnapshot

    func scan(_ request: InstalledSoftwareScanRequest) async -> InstallationSnapshot {
        snapshot
    }

    func reconcileCatalog(
        _ request: InstalledSoftwareScanRequest,
        with current: InstallationSnapshot
    ) async -> InstallationSnapshot {
        snapshot
    }
}

nonisolated final class MutableInstalledSoftwareScanner: InstalledSoftwareScanning, Sendable {
    private let storedSnapshot: Mutex<InstallationSnapshot>

    init(snapshot: InstallationSnapshot = .empty) {
        storedSnapshot = Mutex(snapshot)
    }

    func replace(with snapshot: InstallationSnapshot) {
        storedSnapshot.withLock { $0 = snapshot }
    }

    func scan(_ request: InstalledSoftwareScanRequest) async -> InstallationSnapshot {
        storedSnapshot.withLock { $0 }
    }

    func reconcileCatalog(
        _ request: InstalledSoftwareScanRequest,
        with current: InstallationSnapshot
    ) async -> InstallationSnapshot {
        storedSnapshot.withLock { $0 }
    }
}

@MainActor
func makeMutationService(
    runner: StubBrewProcessRunner,
    scanner: (any InstalledSoftwareScanning)? = nil,
    permissionProbe: (@Sendable () -> AppManagementPermission.Status)? = nil
) -> LocalHomebrewService {
    let softwareScanner = scanner ?? MutableInstalledSoftwareScanner()
    let service = LocalHomebrewService(
        defaults: makeScratchDefaults("mutation-runner-\(UUID().uuidString)")
    ) {
        $0.fileManager = NoFilesFileManager()
        $0.processRunner = runner
        $0.softwareScanner = softwareScanner
        $0.brewBinaryProvider = {
            URL(fileURLWithPath: "/test/bin/brew")
        }
        $0.brewVersionProvider = { "test" }
    }
    if let permissionProbe {
        service.permissionProbe = { _ in
            AppManagementPermission.Assessment(
                status: permissionProbe(),
                evidence: .target
            )
        }
    }
    return service
}

@MainActor
func seedExternalInstallation(
    of cask: Cask,
    version: String?,
    url: URL? = nil,
    in service: LocalHomebrewService
) {
    let bundleName = (cask.packageAppNameCandidates + cask.appArtifactNames).first
        ?? "\(cask.displayName).app"
    let application = makeDetectedApplication(
        bundleName,
        id: "com.example.\(cask.token)",
        version: version,
        url: url
    )
    updateInstallationSnapshot(of: service) {
        $0.detectedApplications.append(application)
        if cask.hasPackageArtifact {
            $0.externalPackageInstallations[cask.token] = ExternalPackageInstallation(
                appBundleNames: [bundleName]
            )
            $0.externalPackageApplicationOwners[cask.token] = application
        } else {
            $0.externalAppNames.insert(bundleName)
            $0.externalApplicationOwners[cask.token] = application
        }
    }
}

@MainActor
func makeMaintenanceHomebrew(
    defaults: UserDefaults,
    executor: RecordingHomebrewCommandExecutor? = nil
) -> LocalHomebrewService {
    LocalHomebrewService(defaults: defaults) {
        $0.softwareScanner = EmptyInstalledSoftwareScanner()
        $0.brewBinaryProvider = { URL(fileURLWithPath: "/opt/homebrew/bin/brew") }
        $0.brewVersionProvider = { "4.6.15" }
        if let executor { $0.commandExecutor = executor }
    }
}

@MainActor
func makeMaintenanceModel(
    probe: RecordingMaintenanceProbe? = nil,
    homebrew: LocalHomebrewService? = nil,
    clearImageCache: @escaping () async -> Void = {},
    latestReleaseTag: @escaping (String, String) async -> String? = { _, _ in nil },
    categories: CategoryService? = nil,
    defaults: UserDefaults? = nil,
    function: String = #function
) -> MaintenanceViewModel {
    let probe = probe ?? RecordingMaintenanceProbe()
    let defaults = defaults ?? makeScratchDefaults(function)
    let service = homebrew ?? makeMaintenanceHomebrew(defaults: defaults)
    let catalog = makeViewModel(
        api: MockBrewAPIClient(),
        categories: categories,
        localHomebrew: service
    )
    return MaintenanceViewModel(
        localHomebrew: service,
        catalog: catalog,
        clearImageCache: clearImageCache,
        probe: probe,
        latestReleaseTag: latestReleaseTag,
        defaults: defaults
    )
}
