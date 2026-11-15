//
//  TapCatalogTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/11/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class TapCatalogTests: XCTestCase {
    func test_browse_search_returns_both_twins() async throws {
        let vm = await makeSUT(official: [makeCask("opensuperwhisper")], taps: ["my-monkeys/tap": ["opensuperwhisper"]])

        vm.selectedSidebar = .discover(.browse)
        vm.searchText = "opensuperwhisper"

        XCTAssertEqual(vm.filteredCasks.map(\.id), ["opensuperwhisper", "my-monkeys/tap/opensuperwhisper"])
    }

    func test_tap_casks_stay_out_of_discover_pages_and_categories() async throws {
        let vm = await makeSUT(official: [makeCask("figma")], taps: ["user/tap": ["tool"]])

        let browseIDs = vm.browseSections.flatMap(\.casks).map(\.id)
        XCTAssertFalse(browseIDs.contains("user/tap/tool"))
        for item in [DiscoverItem.browse, .featured, .topCharts, .recentlyAdded] {
            vm.selectedSidebar = .discover(item)
            XCTAssertFalse(vm.filteredCasks.contains { $0.id == "user/tap/tool" }, "\(item)")
        }
        for categoryID in vm.categoryCounts.keys {
            vm.selectedSidebar = .category(categoryID)
            XCTAssertFalse(vm.filteredCasks.contains { $0.id == "user/tap/tool" }, categoryID)
        }
    }

    func test_covered_tap_casks_join_categories_installed_or_not() async throws {
        let vm = try await makeCoveredTapsSUT(official: [makeCask("figma")])

        vm.selectedSidebar = .category("utilities")
        XCTAssertEqual(Set(vm.filteredCasks.map(\.id)), ["saffsanity/sill/sill", "saffsanity/sill/other"])
        XCTAssertEqual(vm.categoryCounts, ["utilities": 2, "design": 1])
        XCTAssertFalse(vm.browseSections.flatMap(\.casks).contains { $0.thirdPartyTap != nil })
    }

    func test_covered_tap_casks_show_their_category_installed_or_not() async throws {
        let vm = try await makeCoveredTapsSUT(official: [])

        let all = vm.tapCasks(in: "saffsanity/sill") + vm.tapCasks(in: "user/tap")
        let casks = Dictionary(uniqueKeysWithValues: all.map { ($0.token, $0) })
        XCTAssertEqual(vm.categoryPresentation(for: try XCTUnwrap(casks["sill"]))?.mainName, "Utilities")
        XCTAssertEqual(vm.categoryPresentation(for: try XCTUnwrap(casks["other"]))?.mainName, "Utilities")
        XCTAssertNil(vm.categoryPresentation(for: try XCTUnwrap(casks["plain"])))
    }

    func test_an_uninstalled_twin_shows_the_official_category_without_doubling_its_page() async throws {
        let vm = await makeSUT(official: [makeCask("figma")], taps: ["user/tap": ["figma"]], categories: try tapCategories())

        let twin = try XCTUnwrap(vm.catalogCask(for: "user/tap/figma"))
        XCTAssertEqual(vm.categoryPresentation(for: twin)?.mainName, "Design")
        vm.selectedSidebar = .category("design")
        XCTAssertEqual(vm.filteredCasks.map(\.id), ["figma"])
    }

    func test_an_installed_twin_joins_its_category_page() async throws {
        let vm = await makeSUT(
            official: [makeCask("figma")], taps: ["user/tap": ["figma"]],
            installed: [tapInstallation("figma", tap: "user/tap", version: "1.0")], categories: try tapCategories()
        )

        vm.selectedSidebar = .category("design")
        XCTAssertEqual(Set(vm.filteredCasks.map(\.id)), ["figma", "user/tap/figma"])
    }

    func test_tap_sections_cap_at_eight_and_skip_taps_without_casks() async throws {
        let tokens = (1 ... 12).map { "tool-\($0)" }
        let vm = await makeSUT(official: [], taps: ["user/big": tokens, "spotify/public": []])

        XCTAssertEqual(vm.tapSections.map(\.id), ["user/big"])
        XCTAssertEqual(vm.tapSections[0].casks.count, 8)
        XCTAssertEqual(vm.tapSections[0].matchCount, 12, "View All needs the full count")
        XCTAssertEqual(vm.tapCasks(in: "user/big").count, 12)
        XCTAssertEqual(vm.localHomebrew.tapIndex.tapsWithCasks.map(\.name), ["user/big"])
    }

    func test_tap_page_search_filters_sections() async throws {
        let vm = await makeSUT(official: [], taps: ["user/a": ["alpha", "beta"], "user/b": ["gamma"]])

        vm.searchText = "gam"

        XCTAssertEqual(vm.tapSections.map { $0.casks.map(\.token) }, [[], ["gamma"]])
    }

    func test_installed_tap_cask_uses_tap_row() async throws {
        let vm = await makeInstalledSillSUT()

        vm.selectedSidebar = .library(.installed)

        XCTAssertEqual(vm.filteredCasks.map(\.id), ["saffsanity/sill/sill"])
        XCTAssertEqual(vm.filteredCasks.first?.provenance, .tapSource)
    }

    func test_tap_cask_update_follows_brew_outdated() async throws {
        let vm = await makeInstalledSillSUT(official: [makeCask("sill", version: "9.0")], outdated: ["sill"])

        vm.selectedSidebar = .library(.updates)

        XCTAssertEqual(vm.filteredCasks.map(\.id), ["saffsanity/sill/sill"])
    }

    func test_tap_cask_not_listed_by_brew_has_no_update() async throws {
        let vm = await makeInstalledSillSUT()

        vm.selectedSidebar = .library(.updates)

        XCTAssertTrue(vm.filteredCasks.isEmpty)
    }

    func test_tap_cask_never_claims_a_hand_installed_app() async throws {
        let vm = await makeSUT(official: [makeCask("foo", appNames: ["Foo.app"])], taps: ["user/tap": ["foo"]])
        updateInstallationSnapshot(of: vm.localHomebrew) {
            $0.externalApplicationOwners["foo"] = makeDetectedApplication("Foo.app", id: "com.example.foo")
        }
        let tapFoo = try XCTUnwrap(vm.catalogCask(for: "user/tap/foo"))
        let officialFoo = try XCTUnwrap(vm.catalogCask(for: "foo"))

        XCTAssertFalse(vm.localState(for: tapFoo).isAdoptable)
        XCTAssertNil(vm.localState(for: tapFoo).installationSource)
        XCTAssertTrue(vm.localState(for: officialFoo).isAdoptable)
    }

    // MARK: - Helpers

    private func makeSUT(
        official: [Cask],
        taps: [String: [String]],
        installed: [LocalCaskInstallation] = [],
        outdated: Set<String> = [],
        categories: CategoryService? = nil
    ) async -> CaskCatalogViewModel {
        let index = makeTapIndex(taps, source: { "cask \"\($0)\" do\n  name \"\($0)\"\nend\n" })
        let service = LocalHomebrewService(defaults: makeScratchDefaults("tap-catalog-\(UUID().uuidString)")) {
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.brewBinaryProvider = { nil }
            $0.brewVersionProvider = { "test" }
            $0.homebrewOutdatedProvider = { HomebrewOutdatedReport(upgradable: outdated, pinned: []) }
            $0.tapIndexProvider = { index }
        }
        for installation in installed {
            updateInstalledCask(installation, in: service)
        }
        let api = MockBrewAPIClient()
        api.casks = official
        let vm = makeViewModel(api: api, categories: categories, localHomebrew: service)
        await service.refresh()
        await service.refreshHomebrewOutdated()
        await vm.fetchCasks()
        await vm.refreshTaps()
        return vm
    }

    private func makeCoveredTapsSUT(official: [Cask]) async throws -> CaskCatalogViewModel {
        await makeSUT(
            official: official,
            taps: ["saffsanity/sill": ["sill", "other"], "user/tap": ["plain"]],
            installed: [
                tapInstallation("sill", tap: "saffsanity/sill", version: "1.0"),
                tapInstallation("plain", tap: "user/tap", version: "1.0")
            ],
            categories: try tapCategories()
        )
    }

    private func makeInstalledSillSUT(official: [Cask] = [], outdated: Set<String> = []) async -> CaskCatalogViewModel {
        await makeSUT(
            official: official, taps: ["saffsanity/sill": ["sill"]],
            installed: [tapInstallation("sill", tap: "saffsanity/sill", version: "1.0")],
            outdated: outdated
        )
    }

    private func tapCategories() throws -> CategoryService {
        let official = """
        {"version": 1, "generatedDate": "2026-11-13", "releaseTag": null,
         "categories": {"utilities": {"displayName": "Utilities", "icon": "wrench"},
                        "design": {"displayName": "Design", "icon": "paintbrush"}},
         "tokenToCategory": {"figma": {"primary": "design", "secondary": []}}}
        """
        let taps = """
        {"version": 1, "generatedDate": "2026-11-13", "sameAs": {"user/tap/figma": "figma"},
         "casks": {"saffsanity/sill/sill": {"primary": "utilities", "secondary": []},
                   "saffsanity/sill/other": {"primary": "utilities", "secondary": []}}}
        """
        let service = CategoryService()
        service.applyData(try JSONDecoder().decode(CaskCategoryData.self, from: Data(official.utf8)))
        service.applyTapData(try JSONDecoder().decode(TapCatalogData.self, from: Data(taps.utf8)))
        return service
    }

    private func tapInstallation(_ token: String, tap: String, version: String) -> LocalCaskInstallation {
        LocalCaskInstallation(token: token, installedVersion: version, installedAt: nil, appBundleNames: [], tap: tap)
    }
}
