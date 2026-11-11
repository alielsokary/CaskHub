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

    func test_tap_sections_cap_at_eight_and_keep_empty_taps() async throws {
        let tokens = (1 ... 12).map { "tool-\($0)" }
        let vm = await makeSUT(official: [], taps: ["user/big": tokens, "spotify/public": []])

        XCTAssertEqual(vm.tapSections.map(\.id), ["spotify/public", "user/big"])
        XCTAssertEqual(vm.tapSections[0].casks.count, 0)
        XCTAssertEqual(vm.tapSections[1].casks.count, 8)
        XCTAssertEqual(vm.tapCasks(in: "user/big").count, 12)
    }

    func test_tap_page_search_filters_sections() async throws {
        let vm = await makeSUT(official: [], taps: ["user/a": ["alpha", "beta"], "user/b": ["gamma"]])

        vm.searchText = "gam"

        XCTAssertEqual(vm.tapSections.map { $0.casks.map(\.token) }, [[], ["gamma"]])
    }

    func test_installed_tap_cask_uses_tap_row() async throws {
        let vm = await makeSUT(
            official: [], taps: ["saffsanity/sill": ["sill"]],
            installed: [tapInstallation("sill", tap: "saffsanity/sill", version: "1.0")]
        )

        vm.selectedSidebar = .library(.installed)

        XCTAssertEqual(vm.filteredCasks.map(\.id), ["saffsanity/sill/sill"])
        XCTAssertEqual(vm.filteredCasks.first?.provenance, .tapSource)
    }

    func test_tap_cask_update_follows_brew_outdated() async throws {
        let vm = await makeSUT(
            official: [makeCask("sill", version: "9.0")], taps: ["saffsanity/sill": ["sill"]],
            installed: [tapInstallation("sill", tap: "saffsanity/sill", version: "1.0")],
            outdated: ["sill"]
        )

        vm.selectedSidebar = .library(.updates)

        XCTAssertEqual(vm.filteredCasks.map(\.id), ["saffsanity/sill/sill"])
    }

    func test_tap_cask_not_listed_by_brew_has_no_update() async throws {
        let vm = await makeSUT(
            official: [], taps: ["saffsanity/sill": ["sill"]],
            installed: [tapInstallation("sill", tap: "saffsanity/sill", version: "1.0")]
        )

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
        outdated: Set<String> = []
    ) async -> CaskCatalogViewModel {
        let index = TapIndex(
            taps: taps.keys.sorted().map { name in
                TapSummary(
                    name: name, remote: nil, official: false, trusted: false,
                    caskTokens: taps[name, default: []].map { "\(name)/\($0)" }, formulaNames: [], caskFiles: []
                )
            },
            casks: taps.keys.sorted().flatMap { name in
                taps[name, default: []].map {
                    CaskFileTextParser.cask(fromSource: "cask \"\($0)\" do\n  name \"\($0)\"\nend\n", token: $0, tap: name)
                }
            },
            trust: TapTrust(taps: [], casks: [])
        )
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
        let vm = makeViewModel(api: api, localHomebrew: service)
        await service.refresh()
        await service.refreshHomebrewOutdated()
        await vm.fetchCasks()
        await vm.refreshTaps()
        return vm
    }

    private func tapInstallation(_ token: String, tap: String, version: String) -> LocalCaskInstallation {
        LocalCaskInstallation(token: token, installedVersion: version, installedAt: nil, appBundleNames: [], tap: tap)
    }
}
