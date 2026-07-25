//
//  InstallationSnapshotTests.swift
//  CaskHubTests
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
            externalAppNames: ["Firefox.app"],
            detectedApplications: [application],
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
        service.beginOperation(.installing, token: "firefox")
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
            defaults: makeScratchDefaults("snapshot-scanner"),
            softwareScanner: scanner,
            brewVersionProvider: { "Homebrew test" }
        )

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
