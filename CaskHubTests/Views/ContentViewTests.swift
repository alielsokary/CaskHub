//
//  ContentViewTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 16/07/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

final class ContentViewTests: XCTestCase {
    @MainActor
    private final class FocusProbe {
        var focused = true
        var appeared = false
        private(set) var resignCount = 0
        func resign() { resignCount += 1 }
    }

    @MainActor
    private final class CloseProbe {
        var terminationCoordinator: ApplicationTerminationCoordinator?
        var confirmationCount = 0
        var terminationReply: NSApplication.TerminateReply?

        func requestTermination() {
            terminationReply = terminationCoordinator?.applicationShouldTerminate(.shared)
        }
    }

    // MARK: - Harness

    @MainActor
    private func makeWindow(probe: FocusProbe) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Color.clear
            .modifier(ResignFocusOnOutsideClick(
                isFocused: { probe.focused },
                resign: { probe.resign() }
            ))
            .onAppear { probe.appeared = true })
        window.orderFrontRegardless()

        let deadline = Date().addingTimeInterval(2)
        while !probe.appeared, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(probe.appeared, "hosted view never appeared")

        addTeardownBlock { @MainActor in
            window.contentView = NSView()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.close()
        }
        return window
    }

    @MainActor
    private func click(at point: NSPoint, in window: NSWindow) {
        NSApp.postEvent(mouseEvent(.leftMouseUp, at: point, in: window), atStart: false)
        NSApp.sendEvent(mouseEvent(.leftMouseDown, at: point, in: window))
    }

    @MainActor
    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    // MARK: - Tests

    @MainActor
    func test_click_outside_field_editor_resigns_focus() {
        let probe = FocusProbe()
        let window = makeWindow(probe: probe)

        click(at: NSPoint(x: 20, y: 20), in: window)

        XCTAssertEqual(probe.resignCount, 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        XCTAssertEqual(probe.resignCount, 1)
    }

    @MainActor
    func test_click_on_field_editor_keeps_focus() {
        let probe = FocusProbe()
        let window = makeWindow(probe: probe)
        let fieldEditor = NSTextView(frame: NSRect(x: 50, y: 50, width: 100, height: 100))
        fieldEditor.isEditable = false
        fieldEditor.isSelectable = false
        window.contentView!.addSubview(fieldEditor)

        click(at: NSPoint(x: 100, y: 100), in: window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(probe.resignCount, 0)
    }

    @MainActor
    func test_deferred_resign_rechecks_focus() {
        let probe = FocusProbe()
        let window = makeWindow(probe: probe)

        click(at: NSPoint(x: 20, y: 20), in: window)
        probe.focused = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(probe.resignCount, 0)
    }

    @MainActor
    func test_monitor_is_removed_when_view_disappears() {
        let probe = FocusProbe()
        let window = makeWindow(probe: probe)

        window.contentView = NSView()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        click(at: NSPoint(x: 20, y: 20), in: window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(probe.resignCount, 0)
    }

    @MainActor
    func test_close_button_routes_through_active_operation_confirmation() throws {
        let probe = CloseProbe()
        let terminationCoordinator = ApplicationTerminationCoordinator(
            hasActiveOperations: { true },
            requestApplicationTermination: { probe.requestTermination() },
            presentQuitConfirmation: {
                probe.confirmationCount += 1
                return false
            }
        )
        probe.terminationCoordinator = terminationCoordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WindowCloseButtonConfigurator(
            onClose: { terminationCoordinator.requestTermination() },
            onBecomeKey: {}
        ))
        window.orderFrontRegardless()

        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let deadline = Date().addingTimeInterval(2)
        while !(closeButton.target is WindowCloseButtonConfigurator.Coordinator),
              Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(closeButton.target is WindowCloseButtonConfigurator.Coordinator)

        closeButton.performClick(nil)

        XCTAssertEqual(probe.confirmationCount, 1)
        XCTAssertEqual(probe.terminationReply, .terminateCancel)
        window.contentView = NSView()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        window.close()
    }

    @MainActor
    func test_window_configurator_reports_when_its_window_becomes_key() {
        var keyCount = 0
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WindowCloseButtonConfigurator(
            onClose: {},
            onBecomeKey: { keyCount += 1 }
        ))
        window.orderFrontRegardless()

        let closeButton = window.standardWindowButton(.closeButton)
        let deadline = Date().addingTimeInterval(2)
        while !(closeButton?.target is WindowCloseButtonConfigurator.Coordinator),
              Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        keyCount = 0
        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )

        XCTAssertEqual(keyCount, 1)
        window.contentView = NSView()
        window.close()
    }

    func test_sidebar_command_toggles_between_visible_and_hidden() {
        XCTAssertEqual(
            CaskHubViewCommand.sidebarVisibility(afterToggling: .all),
            .detailOnly
        )
        XCTAssertEqual(
            CaskHubViewCommand.sidebarVisibility(afterToggling: .detailOnly),
            .all
        )
    }

    func test_sidebar_command_title_describes_the_next_action() {
        XCTAssertEqual(CaskHubViewCommand.sidebarTitle(for: .all), "Hide Sidebar")
        XCTAssertEqual(CaskHubViewCommand.sidebarTitle(for: .detailOnly), "Show Sidebar")
    }

}

final class SidebarViewTests: XCTestCase {
    @MainActor
    private final class SelectionProbe {
        var selection: SidebarSelection

        init(_ selection: SidebarSelection) {
            self.selection = selection
        }
    }

    @MainActor
    func test_hiding_adopt_apps_moves_adopt_selection_to_installed() {
        assertHiding(SidebarView.showAdoptKey, movesToInstalledFrom: .library(.adopt))
    }

    @MainActor
    func test_hiding_taps_moves_tap_selections_to_installed() {
        assertHiding(SidebarView.showTapsKey, movesToInstalledFrom: .library(.taps))
        assertHiding(SidebarView.showTapsKey, movesToInstalledFrom: .tap("user/tap"))
    }

    @MainActor
    private func assertHiding(_ key: String, movesToInstalledFrom start: SidebarSelection, line: UInt = #line) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: key)
        defer { defaults.removeObject(forKey: key) }

        let probe = SelectionProbe(start)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 226, height: 700),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SidebarView(
            selection: Binding(get: { probe.selection }, set: { probe.selection = $0 }),
            categoryService: CategoryService(),
            adoptableCount: 3,
            tapsCount: 0
        ))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        defaults.set(false, forKey: key)
        let deadline = Date().addingTimeInterval(2)
        while probe.selection == start, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertEqual(probe.selection, .library(.installed), line: line)
        window.contentView = NSView()
        window.close()
    }
}

final class TopBarViewTests: XCTestCase {
    private struct TopBarHarness: View {
        let isUpdatingAll: Bool
        let isUpdatingHomebrew: Bool
        var isRefreshingUpdates = false
        var greedyUpdates: Bool?
        let onAppear: () -> Void

        var body: some View {
            NavigationStack {
                Color.clear
                    .toolbar {
                        TopBarTitle(title: "Updates", summary: "2 casks")
                        CatalogToolbar(
                            sortOption: .constant(.mostPopular),
                            viewMode: .constant(.grid),
                            onUpdateAll: {},
                            isUpdatingAll: isUpdatingAll,
                            isUpdatingHomebrew: isUpdatingHomebrew,
                            onRefreshUpdates: {},
                            isRefreshingUpdates: isRefreshingUpdates,
                            greedyUpdates: greedyUpdates,
                            onToggleGreedy: { _ in }
                        )
                    }
                    .onAppear(perform: onAppear)
            }
        }
    }

    @MainActor
    private final class RenderProbe {
        var appeared = false
    }

    @MainActor
    private func renderTopBar(
        isUpdatingAll: Bool,
        isUpdatingHomebrew: Bool,
        isRefreshingUpdates: Bool = false,
        greedyUpdates: Bool? = nil
    ) {
        let probe = RenderProbe()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: TopBarHarness(
                isUpdatingAll: isUpdatingAll,
                isUpdatingHomebrew: isUpdatingHomebrew,
                isRefreshingUpdates: isRefreshingUpdates,
                greedyUpdates: greedyUpdates
            ) { probe.appeared = true }
        )
        window.orderFrontRegardless()

        let deadline = Date().addingTimeInterval(2)
        while !probe.appeared || (window.toolbar?.items.isEmpty ?? true), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(probe.appeared, "top bar never rendered")
        XCTAssertFalse(window.toolbar?.items.isEmpty ?? true, "toolbar items never installed")

        window.contentViewController = nil
        window.close()
    }

    @MainActor
    func test_refresh_button_renders_refreshing_state() {
        renderTopBar(isUpdatingAll: false, isUpdatingHomebrew: false, isRefreshingUpdates: true)
    }

    @MainActor
    func test_update_all_chip_renders_idle_state() {
        renderTopBar(isUpdatingAll: false, isUpdatingHomebrew: false)
    }

    @MainActor
    func test_update_all_chip_renders_updating_state() {
        renderTopBar(isUpdatingAll: true, isUpdatingHomebrew: false)
        renderTopBar(isUpdatingAll: false, isUpdatingHomebrew: true)
    }

    @MainActor
    func test_greedy_chip_renders_on_and_off_states() {
        renderTopBar(isUpdatingAll: false, isUpdatingHomebrew: false, greedyUpdates: true)
        renderTopBar(isUpdatingAll: false, isUpdatingHomebrew: false, greedyUpdates: false)
    }

    /// Production-boundary check for the reveal sentinel: the browse landing
    /// page's bounded shelves share `caskGrid` with the capped flat grid and
    /// must never fire the global `revealMore()`.
    @MainActor
    func test_browse_landing_page_does_not_consume_reveal_budget() async throws {
        let chunk = CaskCatalogViewModel.revealChunk
        let api = MockBrewAPIClient()
        api.casks = (0 ..< (chunk + 50)).map { makeCask("cask-\($0)") }
        let categories = CategoryService()
        let local = LocalHomebrewService(defaults: makeScratchDefaults("reveal-probe"))
        let vm = makeViewModel(api: api, categories: categories, localHomebrew: local)
        await vm.fetchCasks()
        XCTAssertTrue(vm.hasMoreToReveal)

        let storedViewMode = UserDefaults.standard.string(forKey: "viewMode")
        UserDefaults.standard.set(ViewMode.grid.rawValue, forKey: "viewMode")

        // Tall enough that every browse shelf — and any sentinel wrongly attached
        // to one — materializes inside the lazy containers.
        renderInWindow(vm, categories: categories, local: local, width: 900, height: 3000)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        addTeardownBlock { @MainActor in
            UserDefaults.standard.set(storedViewMode, forKey: "viewMode")
        }

        XCTAssertEqual(
            vm.revealedCount, chunk,
            "browse shelves must not trigger the flat grid's reveal sentinel"
        )
    }

    @MainActor
    func test_catalog_renders_list_and_grid_across_pages() async {
        let api = MockBrewAPIClient()
        api.casks = (0 ..< 12).map { makeCask("cask-\($0)") }
        let categories = CategoryService()
        let local = LocalHomebrewService(defaults: makeScratchDefaults("catalog-render"))
        let vm = makeViewModel(api: api, categories: categories, localHomebrew: local)
        await vm.fetchCasks()

        let storedViewMode = UserDefaults.standard.string(forKey: "viewMode")
        addTeardownBlock { @MainActor in
            UserDefaults.standard.set(storedViewMode, forKey: "viewMode")
        }
        UserDefaults.standard.set(ViewMode.list.rawValue, forKey: "viewMode")

        renderInWindow(vm, categories: categories, local: local)

        vm.selectedSidebar = .discover(.featured)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        UserDefaults.standard.set(ViewMode.grid.rawValue, forKey: "viewMode")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    @MainActor
    func test_catalog_width_is_bounded_at_display_sizes_and_breakpoints() {
        for available in stride(from: CGFloat(250), through: 2200, by: 1) {
            let width = CHSize.catalogWidth(availableWidth: available)
            let count = Int((width + CHSpace.gridGap) / (CHSize.minimumCardWidth + CHSpace.gridGap))
            let cardWidth = (width - CGFloat(count - 1) * CHSpace.gridGap) / CGFloat(count)
            XCTAssertLessThanOrEqual(width, available)
            XCTAssertLessThanOrEqual(width, CHSize.contentWidth)
            XCTAssertTrue((1 ... 4).contains(count))
            XCTAssertTrue((250 ... 280).contains(cardWidth))
        }
        XCTAssertEqual(CHSize.catalogWidth(availableWidth: 730), 574)
        XCTAssertEqual(CHSize.catalogWidth(availableWidth: 853), 853)
        XCTAssertEqual(CHSize.catalogWidth(availableWidth: 1058), 1058)
        XCTAssertEqual(CHSize.catalogWidth(availableWidth: 1506), 1086)
    }

    @MainActor
    func test_catalog_compact_window_does_not_force_horizontal_overflow() async {
        let api = MockBrewAPIClient()
        api.casks = (0 ..< 8).map { makeCask("cask-\($0)") }
        let categories = CategoryService()
        let local = LocalHomebrewService(defaults: makeScratchDefaults("compact-layout"))
        let vm = makeViewModel(api: api, categories: categories, localHomebrew: local)
        await vm.fetchCasks()
        let storedMode = UserDefaults.standard.string(forKey: "viewMode")
        let storedSize = UserDefaults.standard.string(forKey: "catalogTextSize")
        defer {
            UserDefaults.standard.set(storedMode, forKey: "viewMode")
            UserDefaults.standard.set(storedSize, forKey: "catalogTextSize")
        }
        defer { AppStyle.current = .classic }
        for style in AppStyle.allCases {
            AppStyle.current = style
            for mode in [ViewMode.grid, .list] {
                UserDefaults.standard.set(mode.rawValue, forKey: "viewMode")
                UserDefaults.standard.set(CatalogTextSize.largest.rawValue, forKey: "catalogTextSize")
                let window = renderInWindow(vm, categories: categories, local: local, width: 1008)
                XCTAssertLessThanOrEqual(window.contentView?.fittingSize.width ?? .infinity, 1008, "\(style) \(mode)")
            }
        }
    }

    @MainActor
    func test_downloading_capsule_stays_inside_list_action_slot() {
        defer { AppStyle.current = .classic }
        let progress = CaskOperationProgress(
            token: "codexbar",
            displayName: "CodexBar",
            action: .updating,
            phase: .downloading,
            completedBytes: 84_000_000,
            totalBytes: 245_000_000
        )
        for style in AppStyle.allCases {
            AppStyle.current = style
            let capsule = CaskOperationCapsule(
                action: .updating,
                progress: progress,
                isCanceling: false,
                canCancel: false,
                fullWidth: true,
                onCancel: {}
            )
            let slot = CGSize(width: CHSize.listActionWidth, height: 100)
            XCTAssertLessThanOrEqual(NSHostingController(rootView: capsule).sizeThatFits(in: slot).width, slot.width, "\(style)")
        }
    }

    @MainActor
    func test_design_tokens_follow_app_style() {
        defer { AppStyle.current = .classic }
        let environment = EnvironmentValues()

        AppStyle.current = .classic
        XCTAssertGreaterThan(Color.chHairlineStrong.resolve(in: environment).opacity, 0)
        XCTAssertGreaterThan(Color.chActionInstallBorder.resolve(in: environment).opacity, 0)
        XCTAssertEqual(CHRadius.card, 18)
        XCTAssertEqual(CHType.trackingLabel, 2)

        AppStyle.current = .native
        XCTAssertEqual(Color.chHairlineStrong.resolve(in: environment).opacity, 0)
        XCTAssertEqual(Color.chActionInstallBorder.resolve(in: environment).opacity, 0)
        XCTAssertEqual(Color.chBadgeBorder.resolve(in: environment).opacity, 0)
        XCTAssertEqual(CHRadius.card, 14)
        XCTAssertEqual(CHType.trackingLabel, 0.9)
    }

    @MainActor
    func test_error_state_renders_retry_view() async {
        let api = MockBrewAPIClient()
        api.casksError = URLError(.notConnectedToInternet)
        let categories = CategoryService()
        let local = LocalHomebrewService(defaults: makeScratchDefaults("error-render"))
        let vm = makeViewModel(api: api, categories: categories, localHomebrew: local)
        await vm.fetchCasks()
        XCTAssertNotNil(vm.errorMessage)

        renderInWindow(vm, categories: categories, local: local)
    }
}
