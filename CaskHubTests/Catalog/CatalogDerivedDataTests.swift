//
//  CatalogDerivedDataTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 16/11/2026.
//

@testable import CaskHub
import XCTest

/// The catalog-wide projections are rebuilt off the main actor; these drive the real async path.
@MainActor
final class CatalogDerivedDataTests: XCTestCase {
    func test_projections_publish_only_after_the_background_rebuild() async {
        let api = MockBrewAPIClient()
        api.casks = [makeCask("firefox"), makeCask("iterm2")]
        let categories = seededCategories(
            ["firefox": TokenCategoryMapping(primary: "browsers", secondary: [])],
            categories: ["browsers": CategoryDefinition(displayName: "Browsers", icon: "globe")]
        )
        let vm = makeViewModel(api: api, categories: categories)
        await vm.fetchCasks()

        XCTAssertNil(vm.derived.key, "a read schedules the rebuild instead of computing inline")
        XCTAssertTrue(vm.categoryCounts.isEmpty)
        XCTAssertEqual(vm.casks.count, 2, "the raw catalog is never stale")

        await vm.projectionsSettled()
        XCTAssertEqual(vm.categoryCounts, ["browsers": 1])
        XCTAssertEqual(vm.categoryPresentation(for: api.casks[0])?.mainID, "browsers")
    }

    func test_a_newer_rebuild_is_never_overwritten_by_an_older_one() async {
        let local = await makePlatformResolvedHomebrew(defaults: makeScratchDefaults("derived-ordering"))
        let (vm, _) = await makeSUT(casks: [makeCask("firefox"), makeCask("slack")], localHomebrew: local)

        updateInstalledCask(installation("firefox", version: "1.0"), in: local)
        _ = vm.installedCount
        updateInstalledCask(installation("slack", version: "1.0"), in: local)
        _ = vm.installedCount
        await vm.projectionsSettled()

        XCTAssertEqual(Set(vm.installedCasks.map(\.token)), ["firefox", "slack"])
        for _ in 0 ..< 20 { await Task.yield() }
        XCTAssertEqual(vm.installedCount, 2, "the first rebuild finishing late must not win")
    }

    func test_card_state_stays_live_while_the_library_rebuilds() async {
        let local = await makePlatformResolvedHomebrew(defaults: makeScratchDefaults("derived-live-state"))
        let firefox = makeCask("firefox")
        let (vm, _) = await makeSUT(casks: [firefox], localHomebrew: local)
        XCTAssertFalse(vm.localState(for: firefox).isHomebrewInstalled)

        updateInstalledCask(installation("firefox", version: "1.0"), in: local)

        XCTAssertEqual(vm.installedCount, 0, "lists keep the previous snapshot until the rebuild lands")
        XCTAssertTrue(vm.localState(for: firefox).isHomebrewInstalled, "a finished install never flashes as Install")
        await vm.projectionsSettled()
        XCTAssertEqual(vm.installedCount, 1)
    }

    func test_download_counts_rebuild_only_the_popularity_projections() async {
        let (vm, _) = await makeSUT(
            casks: [makeCask("alpha"), makeCask("bravo")],
            analytics: [("alpha", "10"), ("bravo", "20")]
        )
        let before = try? XCTUnwrap(vm.derived.key)
        XCTAssertEqual(vm.browseSections.first?.casks.map(\.token), ["bravo", "alpha"])

        vm.analyticsByPeriod[.days365] = ["alpha": 30, "bravo": 20]
        await vm.projectionsSettled()

        let after = try? XCTUnwrap(vm.derived.key)
        XCTAssertEqual(after?.library, before?.library, "download counts never rebuild library state")
        XCTAssertEqual(after?.presentation, before?.presentation)
        XCTAssertNotEqual(after?.browse, before?.browse)
        XCTAssertEqual(vm.browseSections.first?.casks.map(\.token), ["alpha", "bravo"])
    }
}
