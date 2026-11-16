//
//  ExternallyManagedCasksTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 05/10/2026.
//

@testable import CaskHub
import XCTest

final class ExternallyManagedCasksTests: XCTestCase {
    @MainActor
    func test_installed_separates_external_apps_and_counts_only_visible_sources() async {
        let (model, local) = await makeCatalog()

        await model.projectionsSettled()
        XCTAssertEqual(model.filteredCasks.map(\.token), ["current", "managed"])
        XCTAssertEqual(model.updatableCasks.map(\.token), ["managed"])
        XCTAssertEqual(model.updatesCount, 1)
        XCTAssertEqual(model.filteredExternallyManagedCasks.map(\.token), ["manual", "store", "command", "package"])
        XCTAssertEqual(model.installedCount(includingExternallyManaged: true), 6)
        XCTAssertEqual(model.installedCount(includingExternallyManaged: false), 2)
        XCTAssertEqual(model.filteredCasks.count + model.filteredExternallyManagedCasks.count, 6)

        local.setAdoptIgnored("manual", true)
        await model.projectionsSettled()
        XCTAssertFalse(model.adoptableCasks.contains { $0.token == "manual" })
        XCTAssertTrue(model.filteredExternallyManagedCasks.contains { $0.token == "manual" })

        // Adopting an app moves it out of the external section on the next snapshot.
        updateInstalledCask(installation("manual", version: "1.0"), in: local)
        await model.projectionsSettled()
        XCTAssertEqual(model.filteredExternallyManagedCasks.map(\.token), ["store", "command", "package"])
        XCTAssertEqual(model.filteredCasks.map(\.token), ["manual", "current", "managed"])
        XCTAssertEqual(model.installedCount(includingExternallyManaged: true), 6)
        XCTAssertEqual(model.installedCount(includingExternallyManaged: false), 3)
        XCTAssertEqual(model.updatesCount, 2)

        updateInstallationSnapshot(of: local) {
            $0.externalPackageInstallations = [:]
            $0.externalPackageApplicationOwners = [:]
        }
        await model.projectionsSettled()
        XCTAssertEqual(model.filteredExternallyManagedCasks.map(\.token), ["store", "command"])
        XCTAssertEqual(model.installedCount(includingExternallyManaged: true), 5)

        model.selectedSidebar = .library(.updates)
        XCTAssertEqual(model.filteredCasks.map(\.token), ["manual", "managed"])
    }

    @MainActor
    func test_external_section_uses_installed_search_and_sort_without_changing_sidebar_totals() async {
        let (model, _) = await makeCatalog()
        model.sortOption = .nameZA
        XCTAssertEqual(model.filteredExternallyManagedCasks.map(\.token), ["package", "command", "store", "manual"])

        model.searchText = "store"
        XCTAssertEqual(model.filteredExternallyManagedCasks.map(\.token), ["store"])
        XCTAssertTrue(model.filteredCasks.isEmpty)
        XCTAssertEqual(model.updatesCount, 1)
        XCTAssertEqual(model.installedCount(includingExternallyManaged: true), 6)
        XCTAssertEqual(model.installedCount(includingExternallyManaged: false), 2)

        model.searchText = "not installed"
        XCTAssertTrue(model.filteredExternallyManagedCasks.isEmpty)
        model.searchText = ""
        XCTAssertEqual(model.filteredExternallyManagedCasks.count, 4)
    }

    @MainActor
    private func makeCatalog() async -> (CaskCatalogViewModel, LocalHomebrewService) {
        let local = await makePlatformResolvedHomebrew(defaults: makeScratchDefaults(UUID().uuidString))
        let manual = makeCask("manual", name: "Alpha", version: "2.0", appNames: ["Alpha.app"])
        let store = makeCask(
            "store", name: "Beta", appNames: ["Beta.app"],
            applicationBundleIdentifiers: ["com.example.beta"]
        )
        let package = makeCask(
            "package", name: "Gamma", packageIdentifiers: ["com.example.gamma"],
            packageAppNames: ["Gamma.app"]
        )
        let (model, _) = await makeSUT(casks: [
            manual, store, package,
            makeCask("managed", version: "2.0"),
            makeCask("current"),
            makeCask("absent", name: "Not installed"),
            makeCask("command", binaryNames: ["command"])
        ], localHomebrew: local)
        seedExternalInstallation(of: manual, version: "1.0", in: local)
        seedExternalInstallation(of: package, version: "1.0", in: local)
        updateInstallationSnapshot(of: local) {
            $0.installedCasks = [
                "managed": installation("managed", version: "1.0"),
                "current": installation("current", version: "1.0")
            ]
            $0.macAppStoreAppNames = ["Beta.app"]
            $0.macAppStoreBundleIdentifiers = ["Beta.app": ["com.example.beta"]]
            $0.detectedApplications.append(makeDetectedApplication(
                "Beta.app", id: "com.example.beta", version: "1.0", isMacAppStore: true
            ))
            $0.externalBinaryPaths = ["command": URL(fileURLWithPath: "/external/bin/command")]
        }
        model.selectedSidebar = .library(.installed)
        await model.projectionsSettled()
        return (model, local)
    }
}
