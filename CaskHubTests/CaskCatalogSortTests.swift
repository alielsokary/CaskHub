//
//  CaskCatalogSortTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 24/07/2026.
//

@testable import CaskHub
import XCTest

final class CaskCatalogSortTests: XCTestCase {
    private func detectedApplication(named name: String) -> DetectedApplication {
        DetectedApplication(
            url: URL(fileURLWithPath: "/Applications/\(name)"),
            bundleName: name,
            bundleIdentifier: "com.example.\(name)",
            isMacAppStore: false,
            isDirectlyInApplicationDirectory: true
        )
    }

    @MainActor
    func test_sort_options_order_by_downloads_name_and_added_date() async {
        let recent = RecentlyAddedService()
        recent.addedDates = [
            "bravo": dateString(daysAgo: 1),
            "alpha": dateString(daysAgo: 50)
        ]
        let (vm, _) = await makeSUT(
            casks: [makeCask("alpha"), makeCask("charlie"), makeCask("bravo")],
            analytics: [("bravo", "300"), ("alpha", "200"), ("charlie", "100")],
            recentlyAdded: recent
        )

        vm.sortOption = .mostPopular
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["bravo", "alpha", "charlie"])

        vm.sortOption = .nameAZ
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["alpha", "bravo", "charlie"])

        vm.sortOption = .nameZA
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["charlie", "bravo", "alpha"])

        vm.sortOption = .newest
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["bravo", "alpha", "charlie"])

        vm.sortOption = .oldest
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["alpha", "bravo", "charlie"])
    }

    @MainActor
    func test_library_pages_apply_their_default_sorts() async {
        XCTAssertEqual(
            SortOption.installed,
            [.recentlyInstalled, .mostPopular, .nameAZ, .nameZA]
        )

        let now = Date()
        let local = LocalHomebrewService(defaults: makeScratchDefaults("library-sort-defaults"))
        local.installedCasks = [
            "alpha": LocalCaskInstallation(
                token: "alpha",
                installedVersion: "1.0",
                installedAt: now.addingTimeInterval(-86_400),
                appBundleNames: []
            ),
            "zulu": LocalCaskInstallation(
                token: "zulu",
                installedVersion: "1.0",
                installedAt: now,
                appBundleNames: []
            )
        ]
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("alpha", version: "2.0"),
                makeCask("zulu", version: "2.0"),
                makeCask("able", appNames: ["Able.app"]),
                makeCask("bravo", appNames: ["Bravo.app"])
            ],
            localHomebrew: local
        )
        local.externalApplicationOwners = [
            "able": detectedApplication(named: "Able.app"),
            "bravo": detectedApplication(named: "Bravo.app")
        ]

        vm.selectedSidebar = .library(.installed)
        XCTAssertEqual(vm.sortOption, .recentlyInstalled)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["zulu", "alpha", "able", "bravo"])

        vm.selectedSidebar = .library(.updates)
        XCTAssertEqual(vm.sortOption, .nameAZ)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["alpha", "zulu"])

        vm.selectedSidebar = .library(.adopt)
        XCTAssertEqual(vm.sortOption, .nameAZ)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["able", "bravo"])
    }
}
