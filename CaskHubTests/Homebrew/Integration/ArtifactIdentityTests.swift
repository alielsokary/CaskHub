//
//  ArtifactIdentityTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 20/09/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class ArtifactIdentityTests: XCTestCase {
    func test_generic_app_artifact_reaches_real_scanner_and_preserves_adoption_preflight() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artifact-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApplicationBundle(in: root, named: "Verified.app", bundleIdentifier: "org.example.verified")
        let launcher = RecordingApplicationLauncher()
        let local = LocalHomebrewService(defaults: makeScratchDefaults("artifact-scanner")) {
            $0.applicationDirectories = [root]
            $0.applicationLauncher = launcher
        }
        let categories = CategoryService()
        let data = Data(#"""
        {"version":2,"generatedDate":"2026-09-20","categories":{},"tokenToCategory":{},
         "appIdentities":{"verified":[{"bundleName":"Verified.app","bundleIdentifier":"org.example.verified"}]}}
        """#.utf8)
        categories.applyData(try JSONDecoder().decode(CaskCategoryData.self, from: data))
        var cask = makeCask("verified")
        cask.artifacts = try JSONDecoder().decode([ArtifactStanza].self, from: Data(#"""
        [{"artifact":["Verified.app",{"target":"$APPDIR/Verified.app"}]},
         {"binary":["Verified.app/Contents/MacOS/needed-command"]}]
        """#.utf8))
        let api = MockBrewAPIClient()
        api.casks = [cask]
        let viewModel = makeViewModel(api: api, categories: categories, localHomebrew: local)

        await viewModel.fetchCasks()

        let enriched = try XCTUnwrap(viewModel.casks.first)
        XCTAssertFalse(enriched.isCLI)
        XCTAssertEqual(enriched.appArtifactNames, ["Verified.app"])
        XCTAssertEqual(enriched.applicationBundleIdentifiers, ["org.example.verified"])
        let state = local.localState(for: enriched)
        XCTAssertEqual(state.installationSource, .externalApplication)
        XCTAssertEqual(state.adoptionPlan?.execution, .adoptApplication)
        XCTAssertTrue(state.canOpen)
        XCTAssertEqual(local.adoptBlockedByMissingComponent(enriched), "needed-command")
        local.open(enriched)
        XCTAssertEqual(launcher.lastOpenedURL?.standardizedFileURL, app.standardizedFileURL)
    }

    func test_generic_app_receipt_and_catalog_agree_on_safe_destinations() throws {
        for target in ["$APPDIR/Verified.app", "/Applications/Verified.app"] {
            let artifact = "{\"artifact\":[\"Verified.app\",{\"target\":\"\(target)\"}]}"
            let stanza = try JSONDecoder().decode(ArtifactStanza.self, from: Data(artifact.utf8))
            let receipt = try InstallReceipt(jsonData: Data("{\"uninstall_artifacts\":[\(artifact)]}".utf8))
            XCTAssertEqual(stanza.appNames, ["Verified.app"])
            XCTAssertEqual(receipt.appBundleNames, stanza.appNames)
        }
    }

    func test_generic_artifacts_do_not_turn_other_install_locations_into_apps() throws {
        for target in [
            "/Library/Verified.app", "/Applications/Suite/Verified.app", "/Applications/../Library/Verified.app",
            "$HOMEBREW_PREFIX/Verified.app", "/Applications/Tool.jar", "/Applications/*.app", "/Applications/Renamed.app"
        ] {
            let artifact = "{\"artifact\":[\"Verified.app\",{\"target\":\"\(target)\"}]}"
            let stanza = try JSONDecoder().decode(ArtifactStanza.self, from: Data(artifact.utf8))
            let receipt = try InstallReceipt(jsonData: Data("{\"uninstall_artifacts\":[\(artifact)]}".utf8))
            XCTAssertTrue(stanza.appNames.isEmpty, target)
            XCTAssertTrue(receipt.appBundleNames.isEmpty, target)
        }
        XCTAssertNil(ArtifactStanza.applicationArtifactName(source: "../Verified.app", target: "$APPDIR/Verified.app"))
    }
    func test_verified_package_payload_names_reach_receipt_scanner_and_revoke_cleanly() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("package-identity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApplicationBundle(in: root, named: "Airtool 2.app", bundleIdentifier: "com.intuitibits.airtool2")
        let resolver = PackageReceiptResolver { args in
            args == ["--pkgs"] ? "com.intuitibits.airtool2.pkg" : "Applications/Airtool 2.app/Contents/Info.plist"
        }
        let scanner = HomebrewInstallationScanner(packageReceiptResolver: resolver)
        let local = LocalHomebrewService(defaults: makeScratchDefaults("package-manifest-scanner")) {
            $0.applicationDirectories = [root]
            $0.softwareScanner = scanner
        }
        let categories = CategoryService()
        let data = Data(#"""
        {"version":2,"generatedDate":"2026-09-20","categories":{},"tokenToCategory":{},
         "appIdentities":{"airtool":[{"bundleName":"Airtool 2.app","bundleIdentifier":"com.intuitibits.airtool2",
         "packageIdentifier":"com.intuitibits.airtool2.pkg","installedPath":"/Applications/Airtool 2.app"}]}}
        """#.utf8)
        var metadata = try JSONDecoder().decode(CaskCategoryData.self, from: data)
        categories.applyData(metadata)
        let api = MockBrewAPIClient()
        api.casks = [makeCask("airtool", name: "Airtool", packageIdentifiers: ["com.intuitibits.airtool2.pkg"])]
        let viewModel = makeViewModel(api: api, categories: categories, localHomebrew: local)

        await viewModel.fetchCasks()

        let enriched = try XCTUnwrap(viewModel.casks.first)
        XCTAssertEqual(enriched.catalogPackageAppNames, ["Airtool 2.app"])
        XCTAssertEqual(enriched.applicationBundleIdentifiers, ["com.intuitibits.airtool2"])
        XCTAssertEqual(local.localState(for: enriched).installationSource, .packageInstaller)
        XCTAssertTrue(local.localState(for: enriched).canOpen)

        try makeApplicationBundle(in: root, named: "Airtool 2.app", bundleIdentifier: "org.unrelated.app")
        await viewModel.fetchCasks()
        XCTAssertNil(local.localState(for: viewModel.casks[0]).installationSource)

        try makeApplicationBundle(in: root, named: "Airtool 2.app", bundleIdentifier: "com.intuitibits.airtool2")
        let secondRoot = root.appendingPathComponent("second-directory")
        try makeApplicationBundle(in: secondRoot, named: "Airtool 2.app", bundleIdentifier: "com.intuitibits.airtool2")
        let registration = InstallationCatalogBuilder().build([enriched])
        let duplicateScan = await scanner.scan(InstalledSoftwareScanRequest(
            applicationDirectories: [root, secondRoot], caskroomURL: nil,
            catalog: registration.installationCatalog, applicationSignatures: registration.applicationSignatures,
            packageSignatures: registration.packageSignatures
        ))
        XCTAssertTrue(duplicateScan.externalPackageInstallations.isEmpty)

        metadata.appIdentities = [:]
        categories.applyData(metadata)
        let revoked = categories.addingAppIdentities(to: [enriched])[0]
        XCTAssertFalse(revoked.packageAppNameCandidates.contains("Airtool 2.app"))
        XCTAssertTrue(revoked.applicationBundleIdentifiers.isEmpty)
    }

    func test_package_payload_names_require_matching_receipts_and_direct_paths() throws {
        let categories = CategoryService()
        let data = Data(#"{"version":2,"generatedDate":"2026-09-20","categories":{},"tokenToCategory":{}}"#.utf8)
        var metadata = try JSONDecoder().decode(CaskCategoryData.self, from: data)
        let cask = makeCask("airtool", name: "Airtool", packageIdentifiers: ["com.intuitibits.airtool2.pkg"])
        for (identifier, path) in [
            ("unrelated.pkg", "/Applications/Airtool 2.app"),
            ("com.intuitibits.airtool2.pkg", "/Library/Airtool 2.app"),
            ("com.intuitibits.airtool2.pkg", "/Applications/Suite/Airtool 2.app"),
            ("com.intuitibits.airtool2.pkg", "/Applications/Other.app")
        ] {
            metadata.appIdentities = ["airtool": [CaskAppIdentity(
                bundleName: "Airtool 2.app", bundleIdentifier: "com.intuitibits.airtool2",
                packageIdentifier: identifier, installedPath: path
            )]]
            categories.applyData(metadata)
            let result = categories.addingAppIdentities(to: [cask])[0]
            XCTAssertEqual(result.catalogPackageAppNames, [])
            XCTAssertEqual(result.catalogBundleIdentifiers, [])
        }
    }

}

extension ArtifactIdentityTests {
    func test_conditional_package_candidates_require_receipt_path_and_bundle_agreement() async throws {
        for mode in [
            "valid", "relative-location", "bundle-location", "missing-receipt", "wrong-component", "missing-files",
            "wrong-path", "wrong-id", "same-name-wrong-id", "store", "duplicate", "bad-receipt", "wrong-volume", "auxiliary-app"
        ] {
            try await checkConditionalPackage(mode: mode)
        }
    }

    private func checkConditionalPackage(mode: String) async throws {
        let volume = FileManager.default.temporaryDirectory.appendingPathComponent("conditional-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: volume) }
        let apps = volume.appendingPathComponent("Applications")
        let identifier = mode.hasSuffix("wrong-id") ? "org.unrelated.app" : "org.example.optional"
        let app = try makeApplicationBundle(in: apps, named: "Optional.app", bundleIdentifier: identifier)
        if mode == "store" {
            let receipt = app.appendingPathComponent("Contents/_MASReceipt")
            try FileManager.default.createDirectory(at: receipt, withIntermediateDirectories: true)
            try Data().write(to: receipt.appendingPathComponent("receipt"))
        }
        var directories = [apps]
        if mode == "duplicate" {
            let second = volume.appendingPathComponent("Duplicate")
            try makeApplicationBundle(in: second, named: "Optional.app", bundleIdentifier: identifier)
            directories.append(second)
        }
        let replies = try conditionalReceiptReplies(mode: mode, volume: volume)
        let scanner = HomebrewInstallationScanner(packageReceiptResolver: PackageReceiptResolver { replies[$0.joined(separator: " ")] })
        let launcher = RecordingApplicationLauncher()
        let local = LocalHomebrewService(defaults: makeScratchDefaults("conditional-\(mode)")) {
            $0.applicationDirectories = directories
            $0.softwareScanner = scanner
            $0.applicationLauncher = launcher
        }
        let categories = CategoryService()
        let data = Data(#"""
        {"version":2,"generatedDate":"2026-09-20","categories":{},"tokenToCategory":{},
         "packageAppCandidates":{"optional":[{"bundleName":"Optional.app","bundleIdentifier":"org.example.optional",
          "packageIdentifier":"org.example.optional.component","installedPath":"/Applications/Optional.app"}]}}
        """#.utf8)
        categories.applyData(try JSONDecoder().decode(CaskCategoryData.self, from: data))
        let api = MockBrewAPIClient()
        api.casks = [makeCask("optional", name: mode == "auxiliary-app" ? "Catalog Product" : "Optional",
                              packageIdentifiers: ["org.example.*"])]
        let viewModel = makeViewModel(api: api, categories: categories, localHomebrew: local)
        await viewModel.fetchCasks()
        let enriched = try XCTUnwrap(viewModel.casks.first)
        XCTAssertTrue(enriched.applicationBundleIdentifiers.isEmpty, mode)
        XCTAssertTrue(enriched.catalogPackageAppNames.isEmpty, mode)
        let accepted = ["valid", "relative-location", "bundle-location"].contains(mode)
        let state = local.localState(for: enriched)
        XCTAssertEqual(state.installationSource == .packageInstaller, accepted, mode)
        XCTAssertEqual(state.isAdoptable, accepted, mode)
        if accepted {
            XCTAssertTrue(state.canOpen, mode)
            local.open(enriched)
            XCTAssertEqual(launcher.lastOpenedURL?.standardizedFileURL, app.standardizedFileURL, mode)
        }
    }

    private func conditionalReceiptReplies(mode: String, volume: URL) throws -> [String: String] {
        let receipt = "org.example.optional.component"
        let (location, files) = [
            "relative-location": ("/Applications", "Optional.app/Contents/Info.plist"),
            "bundle-location": ("/Applications/Optional.app", "Contents/Info.plist")
        ][mode] ?? ("/", "Applications/Optional.app/Contents/Info.plist")
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "pkgid": receipt, "volume": mode == "wrong-volume" ? "/" : volume.path, "install-location": location
        ], format: .xml, options: 0)
        let xml = try XCTUnwrap(String(data: plist, encoding: .utf8))
        return [
            "--pkgs": mode == "missing-receipt" ? "" : (mode == "wrong-component" ? "org.example.helper" : receipt),
            "--files \(receipt)": mode == "missing-files" ? "" : (mode == "wrong-path" ? "Library/Optional.app" : files),
            "--pkg-info-plist \(receipt)": mode == "bad-receipt" ? "invalid" : xml
        ]
    }

    func test_conditional_candidates_are_revoked_when_the_feed_omits_them() throws {
        let categories = CategoryService()
        var data = try JSONDecoder().decode(CaskCategoryData.self, from: Data(
            #"{"version":2,"generatedDate":"2026-09-20","categories":{},"tokenToCategory":{}}"#.utf8
        ))
        data.packageAppCandidates = ["optional": [PackageApplicationIdentity(
            bundleName: "Optional.app", bundleIdentifier: "org.example.optional",
            packageIdentifier: "org.example.component", installedPath: "/Applications/Optional.app"
        )]]
        categories.applyData(data)
        let cask = makeCask("optional", packageIdentifiers: ["org.example.*"])
        let enriched = categories.addingAppIdentities(to: [cask])[0]
        XCTAssertEqual(enriched.catalogPackageCandidates?.count, 1)
        data.packageAppCandidates = nil
        categories.applyData(data)
        XCTAssertEqual(categories.addingAppIdentities(to: [enriched])[0].catalogPackageCandidates, [])
    }

    func test_conditional_receipt_shared_by_casks_needs_an_unambiguous_owner() {
        let identity = PackageApplicationIdentity(
            bundleName: "Optional.app", bundleIdentifier: "org.example.optional",
            packageIdentifier: "org.example.component", installedPath: "/Applications/Optional.app"
        )
        let signatures = ["optional", "optional-enterprise"].map { token in
            PackageCaskSignature(
                token: token, displayName: "Optional", receiptPatterns: ["org.example.*"],
                appNameCandidates: ["Optional.app"], verifiedBundleIdentifiersByName: [:], receiptCandidates: [identity]
            )
        }
        let receipt = PackageReceiptResolver.Receipt(
            files: "Applications/Optional.app/Contents/Info.plist",
            location: .init(volume: URL(fileURLWithPath: "/"), installLocation: "/")
        )
        let application = makeDetectedApplication("Optional.app", id: "org.example.optional")
        for installed: Set<String> in [[], ["optional"], ["optional", "optional-enterprise"]] {
            let result = PackageReceiptResolver().resolve(
                signatures: signatures, receipts: [identity.packageIdentifier: receipt],
                availableAppNames: [identity.bundleName], applications: [application], homebrewInstalledTokens: installed
            )
            XCTAssertEqual(Set(result.keys), installed.count == 1 ? installed : [])
        }
    }
}
