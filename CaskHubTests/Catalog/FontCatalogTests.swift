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
    func test_fonts_page_lists_fonts_and_discover_pages_list_them_like_apps() async {
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("firefox"),
                makeCask("font-fira-code", name: "Fira Code"),
                makeCask("font-inter", name: "Inter"),
                Cask.preview(token: "font-old", name: "Old Font", disabled: true),
                makeCask("node@18")
            ],
            analytics: [("font-inter", "900"), ("firefox", "500"), ("font-fira-code", "100")]
        )

        XCTAssertEqual(vm.fontCount, 2, "retired fonts are found by search, not counted")
        vm.selectedSidebar = .fonts
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["font-inter", "font-fira-code"])
        vm.searchText = "fira"
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["font-fira-code"])
        vm.searchText = "font"
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["font-inter", "font-fira-code", "font-old"])

        vm.selectedSidebar = .discover(.topCharts)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["font-inter", "firefox", "font-fira-code"])
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

    func test_fonts_sidebar_row_and_font_tile_render() {
        render(
            SidebarView(selection: .constant(.fonts), categoryService: CategoryService(), fontCount: 2617)
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
