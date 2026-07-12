//
//  AnalyticsTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/07/2026.
//

@testable import CaskHub
import XCTest

private final class SpyAnalyticsProvider: AnalyticsProvider {
    var startedWith: [Bool] = []
    var enabledChanges: [Bool] = []
    var signals: [(name: String, parameters: [String: String])] = []

    func start(enabled: Bool) { startedWith.append(enabled) }
    func setEnabled(_ enabled: Bool) { enabledChanges.append(enabled) }
    func send(_ signalName: String, parameters: [String: String]) {
        signals.append((signalName, parameters))
    }
}

final class AnalyticsTests: XCTestCase {
    private var spy: SpyAnalyticsProvider!
    private var originalProvider: AnalyticsProvider!

    override func setUp() {
        super.setUp()
        spy = SpyAnalyticsProvider()
        originalProvider = Analytics.provider
        Analytics.provider = spy
        UserDefaults.standard.removeObject(forKey: Analytics.enabledKey)
    }

    override func tearDown() {
        Analytics.provider = originalProvider
        UserDefaults.standard.removeObject(forKey: Analytics.enabledKey)
        super.tearDown()
    }

    private var lastSignal: (name: String, parameters: [String: String])? {
        spy.signals.last
    }

    // MARK: - Opt-out state

    func test_analytics_is_enabled_by_default() {
        XCTAssertTrue(Analytics.isEnabled)
    }

    func test_is_enabled_reflects_stored_opt_out() {
        UserDefaults.standard.set(false, forKey: Analytics.enabledKey)
        XCTAssertFalse(Analytics.isEnabled)
    }

    func test_start_passes_stored_setting_to_provider() {
        UserDefaults.standard.set(false, forKey: Analytics.enabledKey)
        Analytics.start()
        XCTAssertEqual(spy.startedWith, [false])
    }

    func test_refresh_forwards_current_setting_to_provider() {
        UserDefaults.standard.set(false, forKey: Analytics.enabledKey)
        Analytics.refresh()
        UserDefaults.standard.set(true, forKey: Analytics.enabledKey)
        Analytics.refresh()
        XCTAssertEqual(spy.enabledChanges, [false, true])
    }

    // MARK: - Cask action events

    func test_cask_action_completed_maps_actions_to_past_tense_signals() {
        Analytics.caskActionCompleted(.installing, token: "firefox")
        Analytics.caskActionCompleted(.uninstalling, token: "firefox")
        Analytics.caskActionCompleted(.updating, token: "firefox")

        XCTAssertEqual(
            spy.signals.map(\.name),
            ["Cask.installed", "Cask.uninstalled", "Cask.updated"]
        )
        XCTAssertEqual(lastSignal?.parameters, ["cask": "firefox"])
    }

    func test_cask_action_completed_ignores_app_launches() {
        Analytics.caskActionCompleted(.opening, token: "firefox")
        XCTAssertTrue(spy.signals.isEmpty)
    }

    func test_cask_action_failed_sends_base_verb_and_token() {
        Analytics.caskActionFailed(.updating, token: "iterm2")
        XCTAssertEqual(lastSignal?.name, "Cask.actionFailed")
        XCTAssertEqual(lastSignal?.parameters, ["action": "update", "cask": "iterm2"])
    }

    func test_cask_action_failed_ignores_app_launches() {
        Analytics.caskActionFailed(.opening, token: "firefox")
        XCTAssertTrue(spy.signals.isEmpty)
    }

    // MARK: - Navigation events

    func test_page_opened_maps_discover_pages() {
        Analytics.pageOpened(.discover(.topCharts))
        XCTAssertEqual(lastSignal?.name, "Page.opened")
        XCTAssertEqual(lastSignal?.parameters, ["page": "topCharts"])
    }

    func test_page_opened_maps_library_pages() {
        Analytics.pageOpened(.library(.installed))
        XCTAssertEqual(lastSignal?.parameters, ["page": "installed"])
    }

    func test_page_opened_maps_categories_with_id() {
        Analytics.pageOpened(.category("productivity"))
        XCTAssertEqual(
            lastSignal?.parameters,
            ["page": "category", "category": "productivity"]
        )
    }

    func test_view_all_tapped_carries_destination_parameters() {
        Analytics.viewAllTapped(to: .category("developer-tools"))
        XCTAssertEqual(lastSignal?.name, "Browse.viewAllTapped")
        XCTAssertEqual(
            lastSignal?.parameters,
            ["page": "category", "category": "developer-tools"]
        )
    }

    // MARK: - Search

    func test_search_performed_normalizes_query_and_counts_results() {
        Analytics.searchPerformed(query: "  FireFox ", results: 3)
        XCTAssertEqual(lastSignal?.name, "Search.performed")
        XCTAssertEqual(lastSignal?.parameters, ["query": "firefox", "results": "3"])
    }

    // MARK: - Filters, view mode & settings

    func test_filter_and_settings_event_names_and_parameters() {
        Analytics.sortChanged(.nameAZ)
        Analytics.topChartsPeriodChanged(.days90)
        Analytics.recentWindowChanged(.days30)
        Analytics.viewModeChanged(.list)
        Analytics.themeChanged("Dark")
        Analytics.analyticsReEnabled()

        XCTAssertEqual(spy.signals.map(\.name), [
            "Filter.sortChanged",
            "Filter.periodChanged",
            "Filter.windowChanged",
            "View.modeChanged",
            "Settings.themeChanged",
            "Settings.analyticsEnabled"
        ])
        XCTAssertEqual(spy.signals.map(\.parameters), [
            ["option": "Name (A→Z)"],
            ["period": "90d"],
            ["window": "30d"],
            ["mode": "list"],
            ["theme": "Dark"],
            [:]
        ])
    }

    // MARK: - Crash-report breadcrumbs

    func test_send_records_breadcrumb_regardless_of_analytics_consent() {
        let crashSpy = SpyCrashReporterProvider()
        let originalCrash = CrashReporter.provider
        CrashReporter.provider = crashSpy
        defer { CrashReporter.provider = originalCrash }
        UserDefaults.standard.set(false, forKey: Analytics.enabledKey)

        Analytics.send("Page.opened", parameters: ["page": "installed"])

        XCTAssertEqual(crashSpy.breadcrumbs.last?.message, "Page.opened")
        XCTAssertEqual(crashSpy.breadcrumbs.last?.data, ["page": "installed"])
    }

    func test_send_skips_breadcrumb_when_crash_reporting_is_off() {
        let crashSpy = SpyCrashReporterProvider()
        let originalCrash = CrashReporter.provider
        CrashReporter.provider = crashSpy
        defer {
            CrashReporter.provider = originalCrash
            UserDefaults.standard.removeObject(forKey: CrashReporter.enabledKey)
        }
        UserDefaults.standard.set(false, forKey: CrashReporter.enabledKey)

        Analytics.send("Page.opened")

        XCTAssertTrue(crashSpy.breadcrumbs.isEmpty)
    }
}
