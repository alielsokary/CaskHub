//
//  PackageProductIdentityTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 27/09/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class PackageProductIdentityTests: XCTestCase {
    private let product = PackageApplicationIdentity(
        bundleName: "Renamed.app", bundleIdentifier: "org.example.product",
        packageIdentifier: "org.example.component", installedPath: "/Applications/Renamed.app"
    )

    private let excel = PackageApplicationIdentity(
        bundleName: "Microsoft Excel.app", bundleIdentifier: "com.microsoft.Excel",
        packageIdentifier: "com.microsoft.package.Microsoft_Excel.app", installedPath: "/Applications/Microsoft Excel.app"
    )
    private let autoUpdateLocation = "Library/Caches/com.microsoft.autoupdate.helper/Clones.noindex"

    func test_autoupdated_excel_remains_installed_adoptable_and_launches_without_claiming_office() async throws {
        let volume = FileManager.default.temporaryDirectory.appendingPathComponent("excel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: volume) }
        let apps = volume.appendingPathComponent("Applications")
        let app = try makeApplicationBundle(in: apps, named: excel.bundleName, bundleIdentifier: excel.bundleIdentifier)
        try setApplicationVersion("16.113.3", at: app)
        let replies = try excelReceiptReplies(volume: volume)
        let launcher = RecordingApplicationLauncher()
        let local = LocalHomebrewService(defaults: makeScratchDefaults("autoupdated-excel")) {
            $0.applicationDirectories = [apps]
            $0.softwareScanner = HomebrewInstallationScanner(
                packageReceiptResolver: PackageReceiptResolver { replies[$0.joined(separator: " ")] }
            )
            $0.applicationLauncher = launcher
        }
        let categories = CategoryService()
        categories.applyData(try metadata(products: [
            "microsoft-excel": [excel], "microsoft-office": [], "microsoft-office-businesspro": []
        ]))
        let api = MockBrewAPIClient()
        api.casks = ["microsoft-excel", "microsoft-office", "microsoft-office-businesspro"].map {
            makeCask($0, packageIdentifiers: ["com.microsoft.package.Microsoft_Excel.app"], packageAppNames: [excel.bundleName])
        }
        let viewModel = makeViewModel(api: api, categories: categories, localHomebrew: local)
        await viewModel.fetchCasks()
        let cask = try XCTUnwrap(viewModel.casks.first { $0.token == "microsoft-excel" })
        let state = local.localState(for: cask)
        XCTAssertEqual(state.installationSource, .packageInstaller)
        XCTAssertEqual(state.externalVersion, "16.113.3")
        XCTAssertTrue(state.isAdoptable)
        XCTAssertTrue(state.canOpen)
        viewModel.selectedSidebar = .library(.installed)
        await viewModel.projectionsSettled()
        XCTAssertTrue(viewModel.filteredCasks.isEmpty)
        XCTAssertEqual(viewModel.filteredExternallyManagedCasks.map(\.token), ["microsoft-excel"])
        viewModel.selectedSidebar = .library(.adopt)
        XCTAssertEqual(viewModel.filteredCasks.map(\.token), ["microsoft-excel"])
        for suite in viewModel.casks where suite.token != cask.token {
            XCTAssertNil(local.localState(for: suite).installationSource)
            local.open(suite)
            XCTAssertNil(launcher.lastOpenedURL)
        }
        local.open(cask)
        XCTAssertEqual(launcher.lastOpenedURL?.standardizedFileURL, app.standardizedFileURL)
    }

    private func excelReceiptReplies(volume: URL) throws -> [String: String] {
        // Captured from the external Excel installation in the macOS VM on 03/10/2026.
        // AutoUpdate's receipt describes a staged patch, while the live app remains in /Applications.
        let info = try PropertyListSerialization.data(fromPropertyList: [
            "pkgid": excel.packageIdentifier, "pkg-version": "16.113.26092714",
            "volume": volume.path, "install-location": autoUpdateLocation
        ], format: .xml, options: 0)
        return [
            "--pkgs": excel.packageIdentifier,
            "--pkg-info-plist \(excel.packageIdentifier)": try XCTUnwrap(String(data: info, encoding: .utf8)),
            "--files \(excel.packageIdentifier)": """
            Microsoft Excel.app/Contents/Frameworks/ADAL4.framework/Versions/A/ADAL4.patchfile
            Microsoft Excel.app/Contents/Info.plist
            """
        ]
    }

    func test_autoupdate_receipts_keep_exact_identity_path_and_review_requirements() {
        for mode in ["valid", "unreviewed", "ambiguous", "store", "duplicate-app", "other-location", "other-volume",
                     "wrong-id", "wrong-app-path", "missing-receipt", "missing-files", "helper-only", "absolute-path", "parent-path"] {
            let signature = PackageCaskSignature(
                token: "microsoft-excel", displayName: "Microsoft Excel", receiptPatterns: [excel.packageIdentifier],
                appNameCandidates: [excel.bundleName], verifiedBundleIdentifiersByName: [:], receiptCandidates: [excel],
                productIdentities: mode == "unreviewed" ? nil : [excel]
            )
            let receipt = autoUpdateReceipt(mode)
            let app = autoUpdateApp(mode)
            let variant = PackageCaskSignature(
                token: "excel-variant", displayName: "Excel Variant", receiptPatterns: [excel.packageIdentifier],
                appNameCandidates: [excel.bundleName], verifiedBundleIdentifiersByName: [:],
                receiptCandidates: [], productIdentities: [excel]
            )
            let result = PackageReceiptResolver().resolve(
                signatures: mode == "ambiguous" ? [signature, variant] : [signature],
                receipts: mode == "missing-receipt" ? [:] : [excel.packageIdentifier: receipt],
                availableAppNames: [excel.bundleName], applications: mode == "duplicate-app" ? [app, app] : [app]
            )
            XCTAssertEqual(Set(result.keys), mode == "valid" ? ["microsoft-excel"] : [], mode)
        }
    }

    private func autoUpdateReceipt(_ mode: String) -> PackageReceiptResolver.Receipt {
        let file = "Microsoft Excel.app/Contents/Info.plist"
        let files = ["missing-files": "", "helper-only": "Microsoft Excel.app/Contents/Frameworks/Helper.app/Contents/Info.plist",
                     "absolute-path": "/" + file, "parent-path": "../" + file][mode] ?? file
        return PackageReceiptResolver.Receipt(files: files, location: .init(
            volume: URL(fileURLWithPath: mode == "other-volume" ? "/Volumes/Other" : "/"),
            installLocation: mode == "other-location" ? "Library/Unrelated" : autoUpdateLocation
        ))
    }

    private func autoUpdateApp(_ mode: String) -> DetectedApplication {
        makeDetectedApplication(
            excel.bundleName, id: mode == "wrong-id" ? "org.example.other" : excel.bundleIdentifier,
            isMacAppStore: mode == "store",
            url: URL(fileURLWithPath: mode == "wrong-app-path" ? "/Applications/Other/Microsoft Excel.app" : excel.installedPath)
        )
    }

    func test_reviewed_product_flows_through_scanning_projection_version_and_open() async throws {
        for mode in ["valid", "missing-receipt", "wrong-path", "wrong-id", "store", "store-wrong-id"] {
            try await checkProduct(mode)
        }
    }

    private func checkProduct(_ mode: String) async throws {
        let volume = FileManager.default.temporaryDirectory.appendingPathComponent("product-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: volume) }
        let apps = volume.appendingPathComponent("Applications")
        let identifier = mode.hasSuffix("wrong-id") ? "org.example.other" : product.bundleIdentifier
        let app = try makeApplicationBundle(
            in: apps, named: product.bundleName, bundleIdentifier: identifier, macAppStoreReceipt: mode.hasPrefix("store")
        )
        try setApplicationVersion("2.0", at: app)
        let replies = try receiptReplies(mode, volume: volume)
        let scanner = HomebrewInstallationScanner(packageReceiptResolver: PackageReceiptResolver { replies[$0.joined(separator: " ")] })
        let launcher = RecordingApplicationLauncher()
        let local = LocalHomebrewService(defaults: makeScratchDefaults("reviewed-\(mode)")) {
            $0.applicationDirectories = [apps]
            $0.softwareScanner = scanner
            $0.applicationLauncher = launcher
        }
        let categories = CategoryService()
        categories.applyData(try metadata(products: ["product": [product], "suite": []]))
        let api = MockBrewAPIClient()
        api.casks = [makeCask("product", name: "Different Product Name", packageIdentifiers: ["org.example.*"]),
                     makeCask("suite", name: "Suite", packageIdentifiers: ["org.example.*"], packageAppNames: [product.bundleName])]
        let viewModel = makeViewModel(api: api, categories: categories, localHomebrew: local)
        await viewModel.fetchCasks()
        let enriched = try XCTUnwrap(viewModel.casks.first { $0.token == "product" })
        let suite = try XCTUnwrap(viewModel.casks.first { $0.token == "suite" })
        let expected: CaskInstallationSource? = mode == "valid" ? .packageInstaller : (mode == "store" ? .macAppStore : nil)
        let state = local.localState(for: enriched)
        XCTAssertEqual(state.installationSource, expected, mode)
        XCTAssertEqual(state.externalVersion, expected == nil ? nil : "2.0", mode)
        XCTAssertEqual(state.isAdoptable, mode == "valid", mode)
        XCTAssertEqual(state.canOpen, expected != nil, mode)
        XCTAssertNil(local.localState(for: suite).installationSource, mode)
        XCTAssertFalse(local.localState(for: suite).canOpen, mode)
        viewModel.selectedSidebar = .library(.installed)
        await viewModel.projectionsSettled()
        XCTAssertTrue(viewModel.filteredCasks.isEmpty, mode)
        XCTAssertEqual(viewModel.filteredExternallyManagedCasks.map(\.token), expected == nil ? [] : ["product"], mode)
        viewModel.selectedSidebar = .library(.adopt)
        XCTAssertEqual(viewModel.filteredCasks.map(\.token), mode == "valid" ? ["product"] : [], mode)
        local.open(suite)
        XCTAssertNil(launcher.lastOpenedURL, mode)
        local.open(enriched)
        XCTAssertEqual(launcher.lastOpenedURL?.standardizedFileURL, expected == nil ? nil : app.standardizedFileURL, mode)
        // The pre-registration fallback must enforce the same reviewed store identity.
        updateInstallationSnapshot(of: local) { $0.installationIndex = .empty }
        XCTAssertEqual(local.localState(for: enriched).installationSource, expected, mode)
        XCTAssertNil(local.localState(for: suite).installationSource, mode)
    }

    func test_reviewed_products_revoke_and_invalid_metadata_cannot_reopen_fallback() throws {
        let categories = CategoryService()
        let cask = makeCask("product", packageIdentifiers: ["org.example.*"], packageAppNames: [product.bundleName])
        categories.applyData(try metadata(products: ["product": [product]]))
        let enriched = categories.addingAppIdentities(to: [cask])[0]
        XCTAssertEqual(enriched.catalogPackageProducts, [product])
        for candidates in [[], [product, product], [PackageApplicationIdentity(
            bundleName: product.bundleName, bundleIdentifier: product.bundleIdentifier,
            packageIdentifier: "unrelated.component", installedPath: product.installedPath
        )]] {
            categories.applyData(try metadata(products: ["product": candidates]))
            let rejected = categories.addingAppIdentities(to: [enriched])[0]
            XCTAssertEqual(rejected.catalogPackageProducts, [])
            XCTAssertTrue(rejected.storeAppNames.isEmpty)
        }
        categories.applyData(try metadata(products: nil))
        let legacy = categories.addingAppIdentities(to: [enriched])[0]
        XCTAssertNil(legacy.catalogPackageProducts)
        XCTAssertTrue(legacy.storeAppNames.contains(product.bundleName))
    }

    func test_reviewed_ambiguity_and_homebrew_suite_precedence() throws {
        let categories = CategoryService()
        let casks = [makeCask("product", name: "Product", packageIdentifiers: ["org.example.*"]),
                     makeCask("variant", name: "Product Variant", packageIdentifiers: ["org.example.*"]),
                     makeCask("suite", name: "Suite", packageIdentifiers: ["org.example.*"], packageAppNames: [product.bundleName])]
        let receipt = PackageReceiptResolver.Receipt(
            files: "Renamed.app/Contents/Info.plist", location: .init(volume: URL(fileURLWithPath: "/"), installLocation: "Applications")
        )
        for ambiguous in [false, true] {
            categories.applyData(try metadata(products: ["product": [product], "variant": ambiguous ? [product] : [], "suite": []]))
            let registration = InstallationCatalogBuilder().build(categories.addingAppIdentities(to: casks))
            let storeMatches = InstallationIndexBuilder().resolveMacAppStoreApplications(
                signatures: registration.installationCatalog.macAppStoreSignatures,
                applications: [makeDetectedApplication(product.bundleName, id: product.bundleIdentifier, isMacAppStore: true)],
                installedCasks: [:]
            )
            XCTAssertEqual(Set(storeMatches.keys), ambiguous ? [] : ["product"])
            for managed: Set<String> in [[], ["product"], ["suite"]] {
                let found = PackageReceiptResolver().resolve(
                    signatures: registration.packageSignatures, receipts: [product.packageIdentifier: receipt],
                    availableAppNames: [product.bundleName],
                    applications: [makeDetectedApplication(product.bundleName, id: product.bundleIdentifier)],
                    homebrewInstalledTokens: managed
                )
                let expected: Set<String> = managed.isEmpty ? (ambiguous ? [] : ["product"]) : managed
                XCTAssertEqual(Set(found.keys), expected)
            }
        }
    }

    func test_reviewed_store_product_suppresses_vendor_guesses_but_preserves_other_exact_products() throws {
        let categories = CategoryService()
        categories.applyData(try metadata(products: ["product": [product]]))
        var other = makeCask("other", packageIdentifiers: ["org.example.*"], packageAppNames: [product.bundleName])
        other.catalogBundleIdentifiers = ["org.example.other"]
        var casks = categories.addingAppIdentities(to: [
            makeCask("product", packageIdentifiers: ["org.example.*"]),
            makeCask("legacy-suite", packageIdentifiers: ["org.example.*"], packageAppNames: [product.bundleName])
        ])
        casks.append(other)
        let catalog = InstallationCatalogBuilder().build(casks).installationCatalog
        for (identifier, expected) in [(product.bundleIdentifier, "product"), ("org.example.other", "other")] {
            let matches = InstallationIndexBuilder().resolveMacAppStoreApplications(
                signatures: catalog.macAppStoreSignatures,
                applications: [makeDetectedApplication(product.bundleName, id: identifier, isMacAppStore: true)], installedCasks: [:]
            )
            XCTAssertEqual(Set(matches.keys), [expected])
        }
    }

    private func receiptReplies(_ mode: String, volume: URL) throws -> [String: String] {
        let info = try PropertyListSerialization.data(fromPropertyList: [
            "pkgid": product.packageIdentifier, "volume": volume.path, "install-location": "Applications"
        ], format: .xml, options: 0)
        return [
            "--pkgs": mode == "missing-receipt" ? "" : product.packageIdentifier,
            "--files \(product.packageIdentifier)": mode == "wrong-path" ? "Elsewhere.app/Contents/Info.plist"
                : "Renamed.app/Contents/Info.plist",
            "--pkg-info-plist \(product.packageIdentifier)": try XCTUnwrap(String(data: info, encoding: .utf8))
        ]
    }

    private func metadata(products: [String: [PackageApplicationIdentity]]?) throws -> CaskCategoryData {
        var data = try JSONDecoder().decode(CaskCategoryData.self, from: Data(
            #"{"version":2,"generatedDate":"2026-09-27","categories":{},"tokenToCategory":{}}"#.utf8
        ))
        data.packageProductIdentities = products
        return data
    }
}
