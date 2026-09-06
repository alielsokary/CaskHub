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
    func test_store_tailscale_matches_package_cask_by_manifest_identity() async throws {
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
        let categories = try makeIdentityCategoryService()
        let verified = categories.addingAppIdentities(to: [tailscale])[0]
        let state = service.localState(for: verified)

        XCTAssertEqual(state.installationSource, .macAppStore)
        XCTAssertTrue(state.isPresent)
        XCTAssertFalse(state.isAdoptable)
        XCTAssertTrue(state.canOpen)

        service.openExternalApp(cask: verified)
        XCTAssertEqual(
            launcher.lastOpenedURL?.standardizedFileURL,
            tailscaleApp.standardizedFileURL
        )
    }
}

@MainActor
final class ApplicationIdentityCollisionTests: XCTestCase {
    func test_catalog_scan_rejects_spark_classic_and_apple_motion_collisions() async throws {
        let categories = try makeIdentityCategoryService()
        for hasReceipt in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            for (name, identifier) in [
                ("Spark.app", "com.readdle.smartemail-Mac"),
                ("Spark Desktop.app", "com.readdle.SparkDesktop.appstore"),
                ("Motion.app", "com.apple.motionapp"),
                ("Verified.app", "com.example.verified")
            ] {
                try makeApplicationBundle(
                    in: root, named: name, bundleIdentifier: identifier,
                    macAppStoreReceipt: hasReceipt
                )
            }
            let classicCollision = makeCask("spark-app", appNames: ["Spark.app"])
            let motionCollision = makeCask("motion", appNames: ["Motion.app"])
            let mail = categories.addingAppIdentities(to: [makeCask("readdle-spark", appNames: ["Spark Desktop.app"])])[0]
            let verified = makeCask("verified", appNames: ["Verified.app"], applicationBundleIdentifiers: ["com.example.verified"])
            let service = LocalHomebrewService(defaults: makeScratchDefaults("identity-collisions")) {
                $0.applicationDirectories = [root]
            }
            let scan = ApplicationDiscovery().scan(fileManager: .default, directories: [root])
            updateInstallationSnapshot(of: service) {
                $0.detectedApplications = scan.applications
                $0.externalAppNames = scan.adoptableNames
                $0.macAppStoreAppNames = scan.macAppStoreNames
                $0.macAppStoreBundleIdentifiers = scan.macAppStoreBundleIdentifiers
            }
            // The unregistered fallback must enforce the same identity rules.
            for cask in [classicCollision, motionCollision] {
                XCTAssertFalse(service.localState(for: cask).isPresent)
                XCTAssertFalse(service.localState(for: cask).isAdoptable)
            }
            await service.updatePackageCatalog([classicCollision, motionCollision, mail, verified])
            for cask in [classicCollision, motionCollision] {
                let state = service.localState(for: cask)
                XCTAssertFalse(state.isPresent)
                XCTAssertFalse(state.canOpen)
                XCTAssertNil(state.adoptionPlan)
                await service.requestReplacementAdoption(cask)
                XCTAssertNil(service.operationStore.state(for: cask.token))
            }
            for cask in [mail, verified] {
                let state = service.localState(for: cask)
                XCTAssertEqual(state.installationSource, hasReceipt ? .macAppStore : .externalApplication)
                XCTAssertTrue(state.canOpen)
                XCTAssertEqual(state.isAdoptable, !hasReceipt)
            }
        }
    }

    func test_element_rejects_kushview_package_and_accepts_matrix() async throws {
        let categories = try makeIdentityCategoryService()
        let matrix = categories.addingAppIdentities(to: [makeCask("element", appNames: ["Element.app"])])[0]
        XCTAssertEqual(matrix.applicationBundleIdentifiers, ["im.riot.app"])
        let registration = InstallationCatalogBuilder().build([matrix])
        XCTAssertTrue(registration.packageSignatures.isEmpty)
        // Observed from Kushview's 1.1.1 installer, not Homebrew metadata.
        let receipts = Set(["ElementApp", "ElementVST2", "ElementVST3", "ElementAU", "ElementLV2", "ElementCLAP"]
            .map { "net.kushview.pkg." + $0 })
        for (identifier, expectedPresent) in [("net.kushview.Element", false), ("im.riot.app", true)] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("element-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            try makeApplicationBundle(in: root, named: "Element.app", bundleIdentifier: identifier)
            let scan = ApplicationDiscovery().scan(fileManager: .default, directories: [root])
            XCTAssertEqual(scan.applications.count, 1)
            let packages = PackageReceiptResolver().resolve(
                signatures: registration.packageSignatures, installedReceipts: receipts,
                packageFileLists: ["net.kushview.pkg.ElementApp": "Applications/Element.app"],
                availableAppNames: scan.adoptableNames
            )
            XCTAssertTrue(packages.isEmpty)
            let service = LocalHomebrewService(defaults: makeScratchDefaults("element-collision")) {
                $0.applicationDirectories = [root]
            }
            updateInstallationSnapshot(of: service) {
                $0.detectedApplications = scan.applications
                $0.externalAppNames = scan.adoptableNames
                $0.externalPackageInstallations = packages
            }
            XCTAssertEqual(service.localState(for: matrix).isAdoptable, expectedPresent)
            await service.updatePackageCatalog([matrix])
            let state = service.localState(for: matrix)
            XCTAssertEqual(state.isPresent, expectedPresent)
            XCTAssertEqual(state.isAdoptable, expectedPresent)
            XCTAssertEqual(state.canOpen, expectedPresent)
            XCTAssertEqual(state.adoptionPlan != nil, expectedPresent)
            if !expectedPresent {
                await service.requestReplacementAdoption(matrix)
                XCTAssertNil(service.operationStore.state(for: matrix.token))
            }
        }
    }

    func test_known_conflicting_identifier_cannot_claim_unique_filename() {
        let application = makeDetectedApplication("Motion.app", id: "com.apple.motionapp")
        let expectedIdentifier = "com.electron.motion"
        XCTAssertTrue(ApplicationOwnershipResolver().resolve(
            signatures: [ApplicationCaskSignature(
                token: "motion", appBundleNames: ["Motion.app"],
                bundleIdentifiers: [expectedIdentifier]
            )],
            applications: [application], installedCasks: [:]
        ).isEmpty)
        let storeApp = makeDetectedApplication(
            "Motion.app", id: "com.apple.motionapp", isMacAppStore: true
        )
        XCTAssertTrue(InstallationIndexBuilder().resolveMacAppStoreApplications(
            signatures: [MacAppStoreCaskSignature(
                token: "motion", bundleNames: ["Motion.app"], hasPackageArtifact: false,
                applicationBundleIdentifiers: [expectedIdentifier], packageIdentifiers: []
            )],
            applications: [storeApp], installedCasks: [:]
        ).isEmpty)
    }

    func test_bundle_identifier_prefix_is_not_identity() {
        XCTAssertFalse(ApplicationIdentityMatcher.applicationBundleIdentifier(
            "com.vendor.suite.unrelated", matchesAny: ["com.vendor.suite.app"]
        ))
        XCTAssertFalse(ApplicationIdentityMatcher.applicationBundleIdentifier("", matchesAny: [""]))
        XCTAssertTrue(ApplicationIdentityMatcher.applicationBundleIdentifier(
            "com.vendor.App", matchesAny: ["com.vendor.app"]
        ))
    }
}
