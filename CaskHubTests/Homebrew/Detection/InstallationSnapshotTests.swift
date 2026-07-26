//
//  InstallationSnapshotTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 25/07/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class InstallationSnapshotTests: XCTestCase {
    func test_complete_scan_is_published_with_one_revision_change() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("snapshot"))
        let installed = LocalCaskInstallation(
            token: "firefox",
            installedVersion: "1",
            installedAt: nil,
            appBundleNames: ["Firefox.app"]
        )
        let application = DetectedApplication(
            url: URL(fileURLWithPath: "/Applications/Firefox.app"),
            bundleName: "Firefox.app",
            bundleIdentifier: "org.mozilla.firefox",
            isMacAppStore: false,
            isDirectlyInApplicationDirectory: true
        )
        let snapshot = InstallationSnapshot(
            installedCasks: ["firefox": installed],
            applications: ApplicationInstallationSnapshot(
                externalAppNames: ["Firefox.app"],
                detectedApplications: [application]
            ),
            externalBinaryPaths: [
                "firefox": URL(fileURLWithPath: "/usr/local/bin/firefox")
            ],
            scannedAt: Date(timeIntervalSince1970: 100)
        )

        service.commitInstallationSnapshot(snapshot)

        XCTAssertEqual(service.catalogStateRevision, 1)
        XCTAssertEqual(service.installationSnapshot.installedCasks["firefox"], installed)
        XCTAssertEqual(service.detectedApplications, [application])
        XCTAssertEqual(service.lastRefresh, Date(timeIntervalSince1970: 100))
    }

    func test_operation_changes_do_not_invalidate_catalog_snapshot() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("snapshot-operation"))
        service.mutationCoordinator.beginOperation(
            .installing,
            token: "firefox",
            displayName: "Firefox"
        )
        service.operationStore.send(.setCancellable(true), for: "firefox")
        service.operationStore.send(.requestCancellation, for: "firefox")

        XCTAssertEqual(service.catalogStateRevision, 0)
    }

    func test_refresh_uses_injected_scanner_without_reading_the_machine() async {
        let scanned = InstallationSnapshot(
            installedCasks: [
                "firefox": LocalCaskInstallation(
                    token: "firefox",
                    installedVersion: "2",
                    installedAt: nil,
                    appBundleNames: ["Firefox.app"]
                )
            ],
            scannedAt: Date(timeIntervalSince1970: 200)
        )
        let scanner = StubInstalledSoftwareScanner(
            scanned: scanned,
            reconciled: scanned
        )
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("snapshot-scanner")
        ) {
            $0.softwareScanner = scanner
            $0.brewVersionProvider = { "Homebrew test" }
        }

        await service.refresh()

        XCTAssertEqual(service.installationSnapshot.installedCasks["firefox"]?.installedVersion, "2")
        XCTAssertEqual(service.lastRefresh, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(service.brewVersion, "Homebrew test")
    }
}

private nonisolated struct StubInstalledSoftwareScanner: InstalledSoftwareScanning {
    let scanned: InstallationSnapshot
    let reconciled: InstallationSnapshot

    func scan(_ request: InstalledSoftwareScanRequest) async -> InstallationSnapshot {
        scanned
    }

    func reconcileCatalog(
        _ request: InstalledSoftwareScanRequest,
        with current: InstallationSnapshot
    ) async -> InstallationSnapshot {
        reconciled
    }
}

extension ExternalInstallationTests {
    @MainActor
    func test_store_tailscale_matches_package_cask_by_application_bundle_family() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-tailscale-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let tailscaleApp = try makeApplicationBundle(
            in: root,
            named: "Tailscale.app",
            bundleIdentifier: "io.tailscale.ipn.macos",
            macAppStoreReceipt: true
        )
        let scan = ApplicationDiscovery().scan(
            fileManager: .default, directories: [root]
        )
        let launcher = RecordingApplicationLauncher()
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("store-tailscale")
        ) {
            $0.applicationDirectories = [root]
            $0.applicationLauncher = launcher
        }
        updateInstallationSnapshot(of: service) {
            $0.macAppStoreAppNames = scan.macAppStoreNames
            $0.macAppStoreBundleIdentifiers =
                scan.macAppStoreBundleIdentifiers
            $0.detectedApplications = scan.applications
        }
        let tailscale = makeCask(
            "tailscale-app",
            name: "Tailscale",
            packageIdentifiers: ["com.tailscale.ipn.macsys"],
            applicationBundleIdentifiers: ["io.tailscale.ipn.macsys"]
        )

        XCTAssertTrue(service.isMacAppStoreInstalled(tailscale))
        XCTAssertTrue(service.isPresent(tailscale))
        XCTAssertFalse(service.isAdoptable(tailscale))
        XCTAssertTrue(service.canOpen(tailscale))

        service.openExternalApp(cask: tailscale)
        XCTAssertEqual(
            launcher.lastOpenedURL?.standardizedFileURL,
            tailscaleApp.standardizedFileURL
        )
    }
}
