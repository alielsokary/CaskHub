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
        XCTAssertEqual(SidebarView.libraryRows, [.library(.installed), .library(.updates), .library(.taps)])
        XCTAssertEqual(SidebarView.manageRows(showAdopt: true), [.shelfSetup, .library(.adopt)])
        XCTAssertEqual(SidebarView.manageRows(showAdopt: false), [.shelfSetup])
    }

    func test_tap_badge_shows_outside_the_tap_pages_only() {
        XCTAssertTrue(ContentView.showsTapBadges(on: .discover(.browse)))
        XCTAssertTrue(ContentView.showsTapBadges(on: .library(.installed)))
        XCTAssertFalse(ContentView.showsTapBadges(on: .library(.taps)))
        XCTAssertFalse(ContentView.showsTapBadges(on: .tap("user/tap")))
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

    func test_github_remote_only_for_github_hosts() {
        XCTAssertEqual(
            TapSectionHeader.githubURL(for: "https://github.com/macos-fuse-t/homebrew-cask"),
            URL(string: "https://github.com/macos-fuse-t/homebrew-cask")
        )
        XCTAssertNil(TapSectionHeader.githubURL(for: "https://gitlab.com/u/homebrew-r"))
        XCTAssertNil(TapSectionHeader.githubURL(for: "file:///tmp/repo"))
        XCTAssertNil(TapSectionHeader.githubURL(for: nil))
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
        let index = TapIndex(
            taps: taps.keys.sorted().map { name in
                TapSummary(
                    name: name, remote: "https://github.com/\(name)", official: false, trusted: false, customRemote: false,
                    caskTokens: taps[name, default: []].map { "\(name)/\($0)" }, formulaNames: [], caskFiles: []
                )
            },
            casks: taps.keys.sorted().flatMap { name in
                taps[name, default: []].map { CaskFileTextParser.cask(fromSource: "", token: $0, tap: name) }
            },
            trust: TapTrust(taps: [], casks: [])
        )
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
        let (vm, categories, local) = (sut.vm, sut.categories, sut.local)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(viewModel: vm)
            .environment(categories)
            .environment(local)
            .environment(ImageCacheService())
            .environment(MaintenanceViewModel(
                localHomebrew: local,
                catalog: vm,
                clearImageCache: {},
                probe: RecordingMaintenanceProbe(),
                defaults: makeScratchDefaults("taps-view-maintenance")
            )))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        addTeardownBlock { @MainActor in
            window.contentView = NSView()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.close()
        }
        return window
    }
}
