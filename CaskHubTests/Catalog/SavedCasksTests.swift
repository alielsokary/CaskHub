//
//  SavedCasksTests.swift
//  CaskHubTests
//
//  Created by therustyrobot on 19/11/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

@MainActor
final class SavedCasksTests: XCTestCase {
    private func makeSavedSUT(
        _ casks: [Cask]? = nil,
        defaults: UserDefaults = makeScratchDefaults(),
        local: LocalHomebrewService? = nil
    ) async -> (vm: CaskCatalogViewModel, local: LocalHomebrewService) {
        let local = local ?? LocalHomebrewService(defaults: defaults)
        let casks = casks ?? [makeCask("alpha"), makeCask("bravo"), makeCask("charlie")]
        let (vm, _) = await makeSUT(casks: casks, localHomebrew: local)
        vm.selectedSidebar = .library(.saved)
        return (vm, local)
    }

    func test_saved_page_follows_saves_and_unsaves_and_survives_relaunch() async {
        let defaults = makeScratchDefaults("saved-persist")
        let (vm, local) = await makeSavedSUT(defaults: defaults)
        XCTAssertTrue(vm.filteredCasks.isEmpty)

        local.setSaved("charlie", true)
        local.setSaved("alpha", true)

        XCTAssertEqual(vm.filteredCasks.map(\.token), ["alpha", "charlie"])
        XCTAssertEqual(vm.savedCasks.count, 2)
        XCTAssertEqual(
            LocalHomebrewService(defaults: defaults).savedReferences, ["alpha", "charlie"],
            "saved list survives relaunch"
        )

        local.setSaved("alpha", false)

        XCTAssertEqual(vm.filteredCasks.map(\.token), ["charlie"])
        XCTAssertEqual(LocalHomebrewService(defaults: defaults).savedReferences, ["charlie"])
    }

    func test_saved_references_missing_from_the_catalog_are_not_listed_or_counted() async {
        let (vm, local) = await makeSavedSUT()

        local.setSaved("ghost-app", true)
        local.setSaved("bravo", true)

        XCTAssertEqual(vm.savedCasks.map(\.token), ["bravo"])
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["bravo"])
        XCTAssertTrue(local.savedReferences.contains("ghost-app"), "a cask that returns to the catalog is still saved")
    }

    func test_saved_page_search_only_matches_saved_casks() async {
        let (vm, local) = await makeSavedSUT([makeCask("alpha-one"), makeCask("alpha-two"), makeCask("bravo")])
        local.setSaved("alpha-two", true)
        local.setSaved("bravo", true)

        vm.searchText = "alpha"

        XCTAssertEqual(vm.filteredCasks.map(\.token), ["alpha-two"])
    }

    func test_a_saved_cask_that_is_later_retired_stays_on_the_saved_page() async {
        let retired = Cask.preview(token: "old-tool", disabled: true)
        let (vm, local) = await makeSavedSUT([makeCask("alpha"), retired])

        local.setSaved("old-tool", true)

        XCTAssertEqual(vm.filteredCasks.map(\.token), ["old-tool"])
    }

    func test_toggling_a_save_does_not_change_other_pages() async {
        let (vm, local) = await makeSavedSUT()
        vm.selectedSidebar = .library(.updates)
        let before = vm.filteredCasks.map(\.token)

        local.setSaved("alpha", true)

        XCTAssertEqual(vm.filteredCasks.map(\.token), before)
    }

    func test_saved_page_renders_empty_and_populated_in_grid_and_list() async {
        let local = LocalHomebrewService(defaults: makeScratchDefaults("saved-render"))
        let categories = CategoryService()
        let (vm, _) = await makeSavedSUT(local: local)
        renderInWindow(vm, categories: categories, local: local)

        local.setSaved("alpha", true)
        for mode in [ViewMode.grid, .list] {
            UserDefaults.standard.set(mode.rawValue, forKey: "viewMode")
            let window = renderInWindow(vm, categories: categories, local: local)
            XCTAssertNotNil(window.contentView)
        }
        UserDefaults.standard.removeObject(forKey: "viewMode")
    }
}
