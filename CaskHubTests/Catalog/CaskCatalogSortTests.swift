//
//  CaskCatalogSortTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 24/07/2026.
//

@testable import CaskHub
import XCTest

final class CaskCatalogSortTests: XCTestCase {
    func test_every_bundled_category_has_localized_name_entry() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "categories", withExtension: "json"))
        let catalog = try JSONDecoder().decode(CaskCategoryData.self, from: Data(contentsOf: url))
        let sentinel = "⟪missing⟫"
        for id in catalog.categories.keys {
            let value = Bundle.main.localizedString(forKey: "category.\(id)", value: sentinel, table: nil)
            XCTAssertNotEqual(value, sentinel, "Localizable.xcstrings has no category.\(id) entry")
        }
    }

    private func localState(
        source: CaskInstallationSource,
        cask: Cask,
        hasAvailableUpdate: Bool
    ) -> CaskLocalState {
        CaskLocalState(
            installationSource: source,
            externalVersion: nil,
            adoptionPlan: CaskAdoptionPlan.make(
                installationSource: source,
                installedVersion: nil,
                homebrewVersion: cask.displayVersion,
                installedCaskTokens: [],
                conflictingCaskTokens: []
            ),
            externalCLIPath: nil,
            uninstallAvailability: source == .homebrew
                ? .available
                : .unavailable(reason: "Adopt first"),
            hasAvailableUpdate: hasAvailableUpdate,
            isZombie: false,
            canOpen: true
        )
    }

    @MainActor
    func test_projector_builds_library_and_route_from_explicit_values() {
        let installed = makeCask("installed")
        let adoptable = makeCask("adoptable")
        let input = CatalogLibraryProjectionInput(
            casks: [installed, adoptable],
            localStates: [
                installed.token: localState(
                    source: .homebrew,
                    cask: installed,
                    hasAvailableUpdate: true
                ),
                adoptable.token: localState(
                    source: .externalApplication,
                    cask: adoptable,
                    hasAvailableUpdate: false
                )
            ],
            categoryMappings: [
                installed.token: TokenCategoryMapping(
                    primary: "utilities",
                    secondary: []
                )
            ],
            adoptIgnoredTokens: []
        )

        let library = CatalogProjector.makeLibrary(from: input)
        let filtered = CatalogProjector.makeFiltered(from: CatalogFilteredProjectionInput(
            casks: input.casks,
            library: library,
            selectedSidebar: .library(.updates),
            searchText: "",
            sortOption: .nameAZ,
            downloadCounts: [:],
            recentTokens: [],
            addedDates: [:],
            installedDates: [:],
            searchKeys: [:],
            nameRanks: [:]
        ))

        XCTAssertEqual(library.installedCasks.map(\.token), ["installed", "adoptable"])
        XCTAssertEqual(library.adoptableCasks.map(\.token), ["adoptable"])
        XCTAssertEqual(library.categoryCounts, ["utilities": 1])
        XCTAssertEqual(filtered.map(\.token), ["installed"])
    }

    @MainActor
    private func alternatingCategories(for casks: [Cask]) -> CategoryService {
        let categories = CategoryService()
        categories.applyData(CaskCategoryData(
            version: 1,
            generatedDate: "2026-07-25",
            releaseTag: nil,
            categories: [
                "even": CategoryDefinition(displayName: "Even", icon: "2.circle"),
                "odd": CategoryDefinition(displayName: "Odd", icon: "1.circle")
            ],
            tokenToCategory: Dictionary(
                uniqueKeysWithValues: casks.enumerated().map { index, cask in
                    let category = index.isMultiple(of: 2) ? "even" : "odd"
                    return (cask.token, TokenCategoryMapping(primary: category, secondary: []))
                }
            ),
            iconTokens: nil
        ))
        return categories
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
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["charlie", "bravo", "alpha"])

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
        updateInstallationSnapshot(of: local) {
            $0.installedCasks = [
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
        }
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("alpha", version: "2.0"),
                makeCask("zulu", version: "2.0"),
                makeCask("able", appNames: ["Able.app"]),
                makeCask("bravo", appNames: ["Bravo.app"])
            ],
            localHomebrew: local
        )
        updateInstallationSnapshot(of: local) {
            $0.externalApplicationOwners = [
                "able": makeDetectedApplication("Able.app"),
                "bravo": makeDetectedApplication("Bravo.app")
            ]
        }

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
    func test_repeated_sidebar_projection_performance() async {
        let itemCount = 1_500
        let casks = (0 ..< itemCount).map { makeCask("app-\($0)") }
        let analytics = (0 ..< itemCount).map { ("app-\($0)", "\($0 + 1)") }
        let categories = alternatingCategories(for: casks)
        let (vm, _) = await makeSUT(
            casks: casks,
            analytics: analytics,
            categories: categories
        )
        let routes: [SidebarSelection] = [
            .discover(.browse),
            .category("even"),
            .library(.installed),
            .library(.adopt),
            .category("odd"),
            .discover(.recentlyAdded)
        ]
        for route in routes {
            vm.selectedSidebar = route
            _ = vm.filteredCasks.count
        }
        var checksum = 0

        measure(metrics: [XCTClockMetric()]) {
            var iterationChecksum = 0
            for _ in 0 ..< 20 {
                for route in routes {
                    vm.selectedSidebar = route
                    iterationChecksum += vm.filteredCasks.count
                }
            }
            checksum = iterationChecksum
        }

        XCTAssertEqual(checksum, itemCount * 40)
    }

    func test_bounded_memoization_reuses_multiple_keys_and_evicts_lru() {
        let cache = BoundedMemoizedValues<Int, String>(capacity: 2)
        var buildCount = 0
        func value(for key: Int) -> String {
            cache.value(for: key) {
                buildCount += 1
                return "value-\(key)"
            }
        }

        XCTAssertEqual(value(for: 1), "value-1")
        XCTAssertEqual(value(for: 2), "value-2")
        XCTAssertEqual(value(for: 1), "value-1")
        XCTAssertEqual(buildCount, 2)

        XCTAssertEqual(value(for: 3), "value-3")
        XCTAssertEqual(value(for: 2), "value-2")
        XCTAssertEqual(buildCount, 4)
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
        updateInstalledCask(installation(cask.token, version: "1.0"), in: local)
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
