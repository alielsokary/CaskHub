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
        let application = makeDetectedApplication("Firefox.app", id: "org.mozilla.firefox")
        let snapshot = InstallationSnapshot(
            installedCasks: ["firefox": installed],
            applications: ApplicationInstallationSnapshot(
                externalAppNames: ["Firefox.app"],
                externalPackageApplicationOwners: [:],
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
        XCTAssertEqual(service.installationSnapshot.detectedApplications, [application])
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
        let scanner = FixedInstalledSoftwareScanner(snapshot: scanned)
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

    func test_caskroom_scan_separates_installation_and_last_update_dates() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("cask-dates-\(UUID().uuidString)")
        let caskroom = root.appendingPathComponent("Caskroom")
        let entry = caskroom.appendingPathComponent("firefox")
        let version = entry.appendingPathComponent("1.0")
        let metadata = entry.appendingPathComponent(".metadata")
        let receiptURL = metadata.appendingPathComponent("INSTALL_RECEIPT.json")
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: version, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: metadata, withIntermediateDirectories: true)
        let receiptTimestamp: TimeInterval = 1_700_000_000
        try Data(
            #"{"time": 1700000000, "uninstall_artifacts": []}"#.utf8
        ).write(to: receiptURL)
        let expectedInstalledAt = try entry.resourceValues(
            forKeys: [.creationDateKey]
        ).creationDate

        let installation = HomebrewInstallationScanner.scanCaskroom(
            at: caskroom,
            fileManager: fileManager,
            applicationDirectories: []
        )["firefox"]

        XCTAssertNotNil(expectedInstalledAt)
        XCTAssertEqual(installation?.installedAt, expectedInstalledAt)
        XCTAssertEqual(
            installation?.lastUpdatedAt,
            Date(timeIntervalSince1970: receiptTimestamp)
        )
    }

    func test_local_date_lookup_uses_the_snapshot_token_index() {
        let indexedDate = Date(timeIntervalSince1970: 400)
        let unrelatedDate = Date(timeIntervalSince1970: 500)
        let unrelatedApplication = makeDetectedApplication(
            "Shared.app",
            id: "com.example.unrelated",
            installedAt: unrelatedDate
        )
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("indexed-installation-dates")
        )
        service.commitInstallationSnapshot(InstallationSnapshot(
            applications: ApplicationInstallationSnapshot(
                externalPackageApplicationOwners: ["package": unrelatedApplication],
                detectedApplications: [unrelatedApplication]
            ),
            externalPackageInstallations: [
                "package": ExternalPackageInstallation(
                    appBundleNames: ["Shared.app"]
                )
            ],
            installationDatesByToken: [
                "package": CaskInstallationDates(
                    installedAt: indexedDate,
                    lastUpdatedAt: nil,
                    basis: .applicationBundleAttributes
                )
            ]
        ))
        let cask = makeCask(
            "package",
            packageIdentifiers: ["com.example.package"],
            packageAppNames: ["Shared.app"]
        )

        XCTAssertEqual(service.installationDates(for: cask)?.installedAt, indexedDate)
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
        let state = service.localState(for: tailscale)

        XCTAssertEqual(state.installationSource, .macAppStore)
        XCTAssertTrue(state.isPresent)
        XCTAssertFalse(state.isAdoptable)
        XCTAssertTrue(state.canOpen)

        service.openExternalApp(cask: tailscale)
        XCTAssertEqual(
            launcher.lastOpenedURL?.standardizedFileURL,
            tailscaleApp.standardizedFileURL
        )
    }
}
