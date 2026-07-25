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
}
