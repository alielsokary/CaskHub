//
//  HousePickTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 16/11/2026.
//

@testable import CaskHub
import XCTest

final class HousePickTests: XCTestCase {
    @MainActor private var casks: [Cask] {
        ["a-app", "b-app", "pocket-bard", "font-fira-code", "c-app@beta"].map { makeCask($0) }
    }
    private let analytics = [("a-app", "10"), ("b-app", "900"), ("pocket-bard", "5")]

    @MainActor
    func test_pick_is_hero_whatever_the_sort() async throws {
        let categories = try categoryService(pick: #"{"token": "pocket-bard", "note": "Bard in your pocket"}"#)
        let (vm, _) = await makeSUT(casks: casks, analytics: analytics, categories: categories)

        for sort in SortOption.standard {
            vm.sortOption = sort
            XCTAssertEqual(vm.heroCask?.token, "pocket-bard", "\(sort)")
        }
    }

    @MainActor
    func test_missing_or_unshowable_pick_falls_back_to_most_popular_not_alphabetical() async throws {
        for pick in [nil, #"{"token": "gone-app"}"#, #"{"token": "font-fira-code"}"#, #"{"token": "c-app@beta"}"#] {
            let categories = try categoryService(pick: pick)
            let (vm, _) = await makeSUT(casks: casks, analytics: analytics, categories: categories)
            vm.selectedSidebar = .discover(.topCharts)
            vm.sortOption = .nameAZ
            vm.selectedSidebar = .discover(.browse)

            XCTAssertEqual(vm.heroCask?.token, "b-app", pick ?? "no pick")
        }
    }

    @MainActor
    func test_no_hero_until_popularity_loads_without_a_pick() async throws {
        let categories = try categoryService(pick: nil)
        let (vm, _) = await makeSUT(casks: casks, categories: categories)

        XCTAssertNil(vm.heroCask)
    }

    @MainActor
    func test_new_data_without_a_pick_clears_the_previous_one() throws {
        let service = try categoryService(pick: #"{"token": "pocket-bard"}"#)
        XCTAssertEqual(service.housePick, HousePick(token: "pocket-bard"))

        try service.applyData(decode(pick: nil))

        XCTAssertNil(service.housePick)
    }

    @MainActor
    private func categoryService(pick: String?) throws -> CategoryService {
        let service = CategoryService()
        try service.applyData(decode(pick: pick))
        return service
    }

    private func decode(pick: String?) throws -> CaskCategoryData {
        let pickField = pick.map { #", "housePick": \#($0)"# } ?? ""
        let json = #"{"version": 1, "generatedDate": "2026-11-16", "categories": {}, "tokenToCategory": {}\#(pickField)}"#
        return try JSONDecoder().decode(CaskCategoryData.self, from: Data(json.utf8))
    }
}
