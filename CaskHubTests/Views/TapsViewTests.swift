//
//  TapsViewTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/11/2026.
//

import AppKit
@testable import CaskHub
import SwiftUI
import XCTest

@MainActor
final class TapsViewTests: XCTestCase {
    func test_sidebar_puts_taps_in_library_and_adopt_under_manage() {
        let base: [SidebarSelection] = [.library(.installed), .library(.updates), .library(.saved)]
        XCTAssertEqual(SidebarView.libraryRows(showTaps: true), base + [.library(.taps)])
        XCTAssertEqual(SidebarView.libraryRows(showTaps: false), base)
        XCTAssertEqual(SidebarView.manageRows(showAdopt: true), [.shelfSetup, .library(.adopt)])
        XCTAssertEqual(SidebarView.manageRows(showAdopt: false), [.shelfSetup])
    }

    func test_tap_badge_shows_outside_the_tap_pages_only() {
        XCTAssertFalse(ContentView.isTapsPage(.discover(.browse)))
        XCTAssertFalse(ContentView.isTapsPage(.library(.installed)))
        XCTAssertTrue(ContentView.isTapsPage(.library(.taps)))
        XCTAssertTrue(ContentView.isTapsPage(.tap("user/tap")))
    }

    func test_taps_icon_exists() {
        XCTAssertNotNil(NSImage(systemSymbolName: LibraryItem.taps.icon, accessibilityDescription: nil))
    }

    func test_tap_page_lists_every_cask_of_that_tap() async {
        let vm = await makeSUT(taps: ["user/big": (1 ... 12).map { "tool-\($0)" }, "user/small": ["one"]]).vm

        vm.selectedSidebar = .tap("user/big")

        XCTAssertEqual(vm.filteredCasks.count, 12)
        XCTAssertTrue(vm.filteredCasks.allSatisfy { $0.tap == "user/big" })
    }

    func test_tap_count_text() {
        let tap = TapSummary(
            name: "user/tap", remote: nil, official: false, trusted: false, customRemote: false,
            caskTokens: ["user/tap/a"], formulaNames: ["user/tap/f1", "user/tap/f2"], caskFiles: []
        )

        XCTAssertEqual(TapSectionHeader.countText(for: tap), "1 cask · 2 formulae")
        let caskOnly = TapSummary(
            name: "user/casks", remote: nil, official: false, trusted: false, customRemote: false,
            caskTokens: ["user/casks/a", "user/casks/b"], formulaNames: [], caskFiles: []
        )
        XCTAssertEqual(TapSectionHeader.countText(for: caskOnly), "2 casks")
    }

    func test_repository_link_for_web_remotes_on_any_host() {
        XCTAssertEqual(
            URL.web("https://github.com/macos-fuse-t/homebrew-cask"),
            URL(string: "https://github.com/macos-fuse-t/homebrew-cask")
        )
        XCTAssertEqual(
            URL.web("https://gitlab.com/u/homebrew-r.git"),
            URL(string: "https://gitlab.com/u/homebrew-r.git")
        )
        XCTAssertNil(URL.web("file:///tmp/repo"))
        XCTAssertNil(URL.web("git@gitlab.com:u/homebrew-r.git"))
    }

    func test_cloning_line_names_the_folder_brew_creates() {
        let remote = URL(string: "https://gitlab.com/group/homebrew-tools")
        let gitlab = TapAddRequest(tapName: "group/tools", remoteURL: remote, caskToken: nil)
        XCTAssertEqual(gitlab.cloneFolder, "…/Taps/group/homebrew-tools")
        XCTAssertEqual(gitlab.sourceText, "gitlab.com/group/homebrew-tools")
    }

    func test_page_analytics_never_names_a_tap() {
        let spy = SpyAnalyticsProvider()
        let original = Analytics.metrics
        let originalDefaults = Analytics.defaults
        Analytics.metrics = spy
        Analytics.defaults = makeScratchDefaults("taps-analytics")
        Analytics.openedPages.removeAll()
        defer {
            Analytics.metrics = original
            Analytics.defaults = originalDefaults
        }

        Analytics.pageOpened(.tap("saffsanity/sill"))
        Analytics.pageOpened(.library(.taps))

        XCTAssertEqual(spy.signals.map(\.parameters), [["page": "tap"], ["page": "taps"]])
    }

    func test_renders_empty_state_sections_and_tap_page() async {
        let empty = await makeSUT(taps: [:])
        empty.vm.selectedSidebar = .library(.taps)
        render(empty)

        let sut = await makeSUT(taps: ["user/big": (1 ... 12).map { "tool-\($0)" }, "spotify/public": []])
        sut.vm.selectedSidebar = .library(.taps)
        let window = render(sut)
        sut.vm.selectedSidebar = .tap("user/big")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNotNil(window.contentView)
    }

    // MARK: - Helpers

    private struct SUT {
        let vm: CaskCatalogViewModel
        let categories: CategoryService
        let local: LocalHomebrewService
    }

    private func makeSUT(taps: [String: [String]]) async -> SUT {
        let index = makeTapIndex(taps, remote: { "https://github.com/\($0)" })
        let local = LocalHomebrewService(defaults: makeScratchDefaults("taps-view-\(UUID().uuidString)")) {
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.brewBinaryProvider = { nil }
            $0.brewVersionProvider = { "test" }
            $0.homebrewOutdatedProvider = { HomebrewOutdatedReport(upgradable: [], pinned: []) }
            $0.tapIndexProvider = { index }
            $0.tapUpdateProvider = {}
        }
        let categories = CategoryService()
        let vm = makeViewModel(api: MockBrewAPIClient(), categories: categories, localHomebrew: local)
        await vm.fetchCasks()
        await vm.refreshTaps()
        return SUT(vm: vm, categories: categories, local: local)
    }

    @discardableResult
    private func render(_ sut: SUT) -> NSWindow {
        renderInWindow(sut.vm, categories: sut.categories, local: sut.local)
    }
}
