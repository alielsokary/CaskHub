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

    @MainActor
    func test_repeated_catalog_projection_performance() async {
        let itemCount = 1_500
        let casks = (0..<itemCount).map { makeCask("app-\($0)") }
        let analytics = (0..<itemCount).map { ("app-\($0)", "\($0 + 1)") }
        let (vm, _) = await makeSUT(casks: casks, analytics: analytics)
        var checksum = 0

        measure(metrics: [XCTClockMetric()]) {
            var iterationChecksum = 0
            for _ in 0..<20 {
                iterationChecksum += vm.filteredCasks.count
                iterationChecksum += vm.installedCount
                iterationChecksum += vm.updatesCount
                iterationChecksum += vm.adoptableCasks.count
                iterationChecksum += vm.categoryCounts.count
            }
            checksum = iterationChecksum
        }

        XCTAssertEqual(checksum, itemCount * 20)
    }

    @MainActor
    func test_cached_projections_invalidate_for_each_catalog_dependency() async {
        let local = LocalHomebrewService(
            defaults: makeScratchDefaults("projection-invalidation")
        )
        let categories = CategoryService()
        let recentlyAdded = RecentlyAddedService()
        let cask = makeCask("example", version: "2.0")
        let (vm, _) = await makeSUT(
            casks: [cask],
            categories: categories,
            recentlyAdded: recentlyAdded,
            localHomebrew: local
        )

        XCTAssertEqual(vm.installedCount, 0)
        local.installedCasks[cask.token] = installation(cask.token, version: "1.0")
        XCTAssertEqual(vm.installedCount, 1)
        XCTAssertEqual(vm.updatesCount, 1)

        vm.selectedSidebar = .discover(.recentlyAdded)
        XCTAssertTrue(vm.filteredCasks.isEmpty)
        recentlyAdded.addedDates[cask.token] = dateString(daysAgo: 1)
        XCTAssertEqual(vm.filteredCasks.map(\.token), [cask.token])

        vm.selectedSidebar = .category("utilities")
        XCTAssertTrue(vm.filteredCasks.isEmpty)
        categories.applyData(CaskCategoryData(
            version: 1,
            generatedDate: "2026-07-25",
            releaseTag: nil,
            totalCasks: 1,
            categories: [
                "utilities": CategoryDefinition(displayName: "Utilities", icon: "wrench")
            ],
            tokenToCategory: [
                cask.token: TokenCategoryMapping(primary: "utilities", secondary: [])
            ],
            iconTokens: nil
        ))
        XCTAssertEqual(vm.filteredCasks.map(\.token), [cask.token])
        XCTAssertEqual(vm.categoryCounts["utilities"], 1)
    }
}
