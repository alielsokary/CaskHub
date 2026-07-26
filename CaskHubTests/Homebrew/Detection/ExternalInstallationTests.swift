//
//  ExternalInstallationTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 25/07/2026.
//

@testable import CaskHub
import XCTest

final class ExternalInstallationTests: XCTestCase {
    @MainActor
    func test_mac_app_store_app_is_installed_but_not_adoptable() {
        let service = LocalHomebrewService()
        updateInstallationSnapshot(of: service) {
            $0.macAppStoreAppNames = ["Canva.app"]
        }
        let canva = makeCask("canva", appNames: ["Canva.app"])
        let state = service.localState(for: canva)

        XCTAssertEqual(state.installationSource, .macAppStore)
        XCTAssertTrue(state.isPresent)
        XCTAssertFalse(state.isAdoptable)
    }

    @MainActor
    func test_package_cask_matches_store_app_by_exact_display_name_but_is_not_adoptable() {
        let service = LocalHomebrewService()
        updateInstallationSnapshot(of: service) {
            $0.macAppStoreAppNames = ["Microsoft Outlook.app"]
            $0.macAppStoreBundleIdentifiers = [
                "Microsoft Outlook.app": ["com.microsoft.Outlook"]
            ]
        }
        let outlook = makeCask(
            "microsoft-outlook",
            name: "Microsoft Outlook",
            packageIdentifiers: ["com.microsoft.package.Microsoft_Outlook.app"]
        )
        let state = service.localState(for: outlook)

        XCTAssertEqual(state.installationSource, .macAppStore)
        XCTAssertTrue(state.isPresent)
        XCTAssertFalse(state.isAdoptable)
    }

    @MainActor
    func test_external_package_app_is_present_launchable_and_adoptable() throws {
        let apps = FileManager.default.temporaryDirectory
            .appendingPathComponent("external-package-\(UUID().uuidString)")
        let app = try makeApplicationBundle(
            in: apps, named: "zoom.us.app", bundleIdentifier: "us.zoom.xos"
        )
        defer { try? FileManager.default.removeItem(at: apps) }

        let launcher = RecordingApplicationLauncher()
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("external-package")
        ) {
            $0.applicationDirectories = [apps]
            $0.applicationLauncher = launcher
        }
        updateInstallationSnapshot(of: service) {
            $0.externalPackageInstallations = [
                "zoom": ExternalPackageInstallation(
                    appBundleNames: ["zoom.us.app"]
                )
            ]
        }
        let zoom = makeCask(
            "zoom",
            name: "Zoom",
            packageIdentifiers: ["us.zoom.pkg.videomeeting"],
            packageAppNames: ["zoom.us.app"]
        )
        let state = service.localState(for: zoom)

        XCTAssertTrue(state.isPresent)
        XCTAssertTrue(state.isAdoptable)
        XCTAssertTrue(state.canOpen)
        XCTAssertEqual(state.installationSource, .packageInstaller)

        service.openExternalApp(cask: zoom)
        XCTAssertEqual(
            launcher.lastOpenedURL?.standardizedFileURL.path,
            app.standardizedFileURL.path
        )
    }

    func test_application_scan_separates_mac_app_store_bundles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("application-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        try makeApplicationBundle(
            in: root, named: "Direct.app", bundleIdentifier: "com.example.direct"
        )
        try makeApplicationBundle(
            in: root,
            named: "Store.app",
            bundleIdentifier: "com.example.store",
            macAppStoreReceipt: true
        )

        let scan = ApplicationDiscovery().scan(
            fileManager: FileManager.default,
            directories: [root]
        )
        XCTAssertEqual(scan.adoptableNames, ["Direct.app"])
        XCTAssertEqual(scan.macAppStoreNames, ["Store.app"])
        XCTAssertEqual(scan.macAppStoreBundleIdentifiers, [
            "Store.app": ["com.example.store"]
        ])
    }

    func test_application_scan_finds_store_app_inside_localized_wrapper() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localized-application-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let wrapper = root.appendingPathComponent("WhatsApp.localized")
        let whatsapp = try makeApplicationBundle(
            in: wrapper,
            named: "WhatsApp.app",
            bundleIdentifier: "net.whatsapp.WhatsApp",
            macAppStoreReceipt: true
        )

        let scan = ApplicationDiscovery().scan(
            fileManager: .default, directories: [root]
        )

        XCTAssertEqual(scan.macAppStoreNames, ["WhatsApp.app"])
        XCTAssertEqual(scan.applications.map(\.url), [whatsapp.standardizedFileURL])
    }

    @MainActor
    func test_nested_store_app_is_present_and_opens_using_its_real_url() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localized-store-open-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let whatsapp = try makeApplicationBundle(
            in: root.appendingPathComponent("WhatsApp.localized"),
            named: "WhatsApp.app",
            bundleIdentifier: "net.whatsapp.WhatsApp",
            macAppStoreReceipt: true
        )
        let scan = ApplicationDiscovery().scan(
            fileManager: .default, directories: [root]
        )
        let launcher = RecordingApplicationLauncher()
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("localized-store-open")
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
        let cask = makeCask("whatsapp", name: "WhatsApp", appNames: ["WhatsApp.app"])
        let state = service.localState(for: cask)

        XCTAssertEqual(state.installationSource, .macAppStore)
        XCTAssertTrue(state.isPresent)
        XCTAssertTrue(state.canOpen)
        XCTAssertFalse(state.isAdoptable)

        service.openExternalApp(cask: cask)
        XCTAssertEqual(
            launcher.lastOpenedURL?.standardizedFileURL,
            whatsapp.standardizedFileURL
        )
    }

    func test_package_metadata_decodes_receipts_and_deleted_apps() throws {
        let json = Data("""
        [{"uninstall": [{
          "pkgutil": ["com.microsoft.teams2", "com.microsoft.audio"],
          "delete": ["/Applications/Microsoft Teams.app", "/Library/Logs/Teams"],
          "quit": "com.microsoft.teams2"
        }]}, {"pkg": ["MicrosoftTeams.pkg"]}]
        """.utf8)
        let stanzas = try JSONDecoder().decode([ArtifactStanza].self, from: json)

        XCTAssertEqual(
            stanzas[0].packageIdentifiers,
            ["com.microsoft.teams2", "com.microsoft.audio"]
        )
        XCTAssertEqual(stanzas[0].deletedAppNames, ["Microsoft Teams.app"])
        XCTAssertEqual(stanzas[0].applicationBundleIdentifiers, ["com.microsoft.teams2"])
        XCTAssertTrue(stanzas[1].keys.contains("pkg"))
    }

    func test_package_receipt_patterns_and_payload_app_names() {
        XCTAssertTrue(PackageReceiptResolver.identifier(
            "org.virtualbox.pkg.virtualbox", matches: "org.virtualbox.pkg.*"
        ))
        XCTAssertFalse(PackageReceiptResolver.identifier(
            "org.virtualbox.extension", matches: "org.virtualbox.pkg.*"
        ))
        XCTAssertEqual(
            PackageReceiptResolver.appBundleNames(inPackageFileList: """
            Applications/VirtualBox.app
            Applications/VirtualBox.app/Contents/MacOS/VirtualBox
            Library/Extensions/VBoxDrv.kext
            """),
            ["VirtualBox.app"]
        )
    }

    @MainActor
    func test_installed_includes_store_and_package_apps_while_adopt_only_includes_package() async {
        let local = LocalHomebrewService(defaults: makeScratchDefaults("external-installed"))
        let store = makeCask("store-app", name: "Store App", appNames: ["Store App.app"])
        let package = makeCask(
            "package-app",
            name: "Package App",
            packageIdentifiers: ["com.example.package"],
            packageAppNames: ["Package App.app"]
        )
        let (vm, _) = await makeSUT(casks: [store, package], localHomebrew: local)
        updateInstallationSnapshot(of: local) {
            $0.externalPackageInstallations = [
                package.token: ExternalPackageInstallation(
                    appBundleNames: ["Package App.app"]
                )
            ]
            $0.installationIndex = CaskInstallationIndex(
                catalogTokens: [store.token, package.token],
                macAppStoreApplications: [
                    store.token: DetectedApplication(
                        url: URL(fileURLWithPath: "/Applications/Store App.app"),
                        bundleName: "Store App.app",
                        bundleIdentifier: "com.example.store-app",
                        isMacAppStore: true,
                        isDirectlyInApplicationDirectory: true
                    )
                ],
                externalCLIPaths: [:]
            )
        }

        vm.selectedSidebar = .library(.installed)
        XCTAssertEqual(Set(vm.filteredCasks.map(\.token)), [store.token, package.token])
        XCTAssertEqual(vm.installedCount, 2)

        vm.selectedSidebar = .library(.adopt)
        XCTAssertEqual(vm.filteredCasks.map(\.token), [package.token])
    }

    func test_partial_sf_symbols_bundle_is_not_launchable_or_scanned() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("partial-sf-symbols-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let stable = root.appendingPathComponent("SF Symbols.app")
        try FileManager.default.createDirectory(
            at: stable.appendingPathComponent("Contents/Resources"),
            withIntermediateDirectories: true
        )
        try makeApplicationBundle(
            in: root,
            named: "SF Symbols Beta.app",
            bundleIdentifier: "com.apple.SFSymbols-beta"
        )

        let discovery = ApplicationDiscovery()
        let scan = discovery.scan(
            fileManager: .default, directories: [root]
        )
        XCTAssertEqual(scan.adoptableNames, ["SF Symbols Beta.app"])
        XCTAssertNil(discovery.metadata(
            at: stable, fileManager: .default
        ))
    }

    @MainActor
    func test_partial_sf_symbols_bundle_cannot_be_opened() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlaunchable-sf-symbols-\(UUID().uuidString)")
        let stable = root.appendingPathComponent("SF Symbols.app")
        try FileManager.default.createDirectory(at: stable, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("unlaunchable-sf-symbols")
        ) {
            $0.applicationDirectories = [root]
        }
        let cask = makeCask(
            "sf-symbols",
            name: "SF Symbols",
            packageIdentifiers: ["com.apple.pkg.SFSymbols"],
            packageAppNames: ["SF Symbols.app"]
        )
        updateInstalledCask(LocalCaskInstallation(
            token: cask.token,
            installedVersion: "8.0",
            installedAt: nil,
            appBundleNames: []
        ), in: service)

        let state = service.localState(for: cask)
        XCTAssertFalse(state.canOpen)
        XCTAssertFalse(state.isZombie)
    }

    func test_stable_sf_symbols_cask_does_not_claim_beta_payload() {
        let signature = PackageCaskSignature(
            token: "sf-symbols",
            displayName: "SF Symbols",
            receiptPatterns: ["com.apple.pkg.SFSymbols"],
            appNameCandidates: ["SF Symbols.app"]
        )

        let result = PackageReceiptResolver().resolve(
            signatures: [signature],
            installedReceipts: ["com.apple.pkg.SFSymbols"],
            packageFileLists: [
                "com.apple.pkg.SFSymbols": "Applications/SF Symbols Beta.app"
            ],
            availableAppNames: ["SF Symbols Beta.app"]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func test_shared_zoom_receipt_resolves_to_one_canonical_cask() {
        let receipt = "us.zoom.pkg.videomeeting"
        let signatures = [
            PackageCaskSignature(
                token: "zoom",
                displayName: "Zoom",
                receiptPatterns: [receipt],
                appNameCandidates: ["Zoom.app", "zoom.us.app"]
            ),
            PackageCaskSignature(
                token: "zoom-for-it-admins",
                displayName: "Zoom for IT Admins",
                receiptPatterns: [receipt],
                appNameCandidates: ["Zoom for IT Admins.app", "zoom.us.app"]
            )
        ]

        let result = PackageReceiptResolver().resolve(
            signatures: signatures,
            installedReceipts: [receipt],
            packageFileLists: [:],
            availableAppNames: ["zoom.us.app"]
        )

        XCTAssertEqual(Set(result.keys), ["zoom"])
        XCTAssertEqual(result["zoom"]?.appBundleNames, ["zoom.us.app"])
    }

    @MainActor
    func test_store_app_with_same_name_but_different_vendor_is_not_the_cask() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("store-shade"))
        updateInstallationSnapshot(of: service) {
            $0.macAppStoreAppNames = ["Shade.app"]
            $0.macAppStoreBundleIdentifiers = [
                "Shade.app": ["com.limit-point.Shade"]
            ]
        }
        let shade = makeCask(
            "shade",
            name: "Shade",
            packageIdentifiers: ["com.shade.shade"]
        )
        let state = service.localState(for: shade)

        XCTAssertNotEqual(state.installationSource, .macAppStore)
        XCTAssertFalse(state.isPresent)
    }

}
