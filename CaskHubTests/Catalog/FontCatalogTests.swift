//
//  FontCatalogTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 01/11/2026.
//

import AppKit
@testable import CaskHub
import SwiftUI
import XCTest

@MainActor
final class FontCatalogTests: XCTestCase {
    func test_fonts_get_their_own_category_and_list_like_apps_except_recently_added() async {
        let recent = RecentlyAddedService()
        recent.addedDates = ["old-app": "2020-01-01T00:00:00Z"]
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("firefox"),
                makeCask("font-fira-code", name: "Fira Code"),
                makeCask("font-inter", name: "Inter"),
                Cask.preview(token: "font-old", name: "Old Font", disabled: true),
                makeCask("node@18")
            ],
            analytics: [("font-inter", "900"), ("firefox", "500"), ("font-fira-code", "100")],
            categories: seededCategories([:], categories: [:]),
            recentlyAdded: recent
        )
        let fonts = SidebarSelection.category(CategoryService.fontsCategoryID)

        XCTAssertEqual(vm.categoryService.displayName(for: CategoryService.fontsCategoryID), "Fonts")
        XCTAssertEqual(vm.categoryCounts[CategoryService.fontsCategoryID], 2, "retired fonts are found by search, not counted")
        vm.selectedSidebar = fonts
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["font-inter", "font-fira-code"])
        XCTAssertEqual(vm.filteredCasks.first.flatMap(vm.categoryPresentation(for:))?.mainName, "Fonts")
        vm.searchText = "font"
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["font-inter", "font-fira-code", "font-old"])

        vm.selectedSidebar = .discover(.topCharts)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["font-inter", "firefox", "font-fira-code"])

        vm.selectedSidebar = .discover(.recentlyAdded)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["firefox"], "unmined fonts would otherwise count as new")
        vm.searchText = "font"
        XCTAssertEqual(vm.filteredCasks.map(\.token), [])
        let shelf = vm.browseSections.first { $0.destination == .discover(.recentlyAdded) }
        XCTAssertEqual(shelf?.casks.map(\.token), ["firefox"])
        let fontShelf = vm.browseSections.first { $0.destination == fonts }
        XCTAssertEqual(fontShelf?.casks.map(\.token), ["font-inter", "font-fira-code"])
    }

    func test_fonts_never_request_icons() async {
        RequestCounter.count = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCounter.self]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("font-icons-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let images = ImageCacheService(session: URLSession(configuration: configuration), diskCache: IconDiskCache(directory: directory))
        images.knownIconTokens = { [] }

        let fontImage = await images.image(for: makeCask("font-inter"))
        XCTAssertNil(fontImage)
        XCTAssertEqual(RequestCounter.count, 0, "fonts ship no app icon, so no lookup can succeed")

        _ = await images.image(for: makeCask("some-app", appNames: ["Some.app"]))
        XCTAssertGreaterThan(RequestCounter.count, 0, "apps still try the icon fallback")
    }

    func test_fonts_category_row_and_font_tile_render() {
        let categories = seededCategories([:], categories: [:])
        XCTAssertTrue(categories.orderedCategories.contains { $0.id == CategoryService.fontsCategoryID })
        render(
            SidebarView(
                selection: .constant(.category(CategoryService.fontsCategoryID)),
                categoryService: categories,
                categoryCounts: [CategoryService.fontsCategoryID: 2617]
            )
            .environment(LocalHomebrewService(defaults: makeScratchDefaults("font-sidebar"))),
            width: 240, height: 900
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCounter.self]
        let images = ImageCacheService(session: URLSession(configuration: configuration))
        images.knownIconTokens = { [] }
        render(CaskIconView(cask: makeCask("font-inter"), size: 38).environment(images), width: 60, height: 60)
    }
}

private final class RequestCounter: URLProtocol {
    nonisolated(unsafe) static var count = 0

    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.count += 1
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
