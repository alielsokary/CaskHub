//
//  AnalyticsTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/07/2026.
//

@testable import CaskHub
import Sentry
import TelemetryDeck
import XCTest

final class AnalyticsTests: XCTestCase {
    var spy: SpyAnalyticsProvider!
    private var originalProvider: AnalyticsProvider!
    private var originalMetrics: SentryMetricsApiProtocol!
    private var originalAnalyticsDefaults: UserDefaults!
    private var originalCrashDefaults: UserDefaults!
    var crashSpy: SpyCrashReporterProvider!
    private var originalCrashProvider: CrashReporterProvider!
    private var originalCaptureCounts: [String: Int]!
    private var originalCrashTestState = false

    override func setUp() {
        super.setUp()
        spy = SpyAnalyticsProvider()
        originalProvider = Analytics.provider
        originalMetrics = Analytics.metrics
        originalAnalyticsDefaults = Analytics.defaults
        originalCrashDefaults = CrashReporter.defaults
        originalCrashProvider = CrashReporter.provider
        originalCaptureCounts = CrashReporter.captureCounts
        originalCrashTestState = CrashReporter.isRunningTests
        crashSpy = SpyCrashReporterProvider()
        Analytics.provider = spy
        Analytics.metrics = spy
        CrashReporter.provider = crashSpy
        CrashReporter.captureCounts = [:]
        CrashReporter.isRunningTests = false
        Analytics.defaults = makeScratchDefaults(
            "analytics-\(ProcessInfo.processInfo.processIdentifier)"
        )
        CrashReporter.defaults = makeScratchDefaults(
            "analytics-crash-\(ProcessInfo.processInfo.processIdentifier)"
        )
        Analytics.openedPages.removeAll()
    }

    override func tearDown() {
        Analytics.provider = originalProvider
        Analytics.metrics = originalMetrics
        Analytics.defaults = originalAnalyticsDefaults
        CrashReporter.defaults = originalCrashDefaults
        CrashReporter.provider = originalCrashProvider
        CrashReporter.captureCounts = originalCaptureCounts
        CrashReporter.isRunningTests = originalCrashTestState
        super.tearDown()
    }

    var lastSignal: (name: String, parameters: [String: String])? { spy.signals.last }

    // MARK: - Opt-out state

    func test_analytics_is_enabled_by_default() {
        XCTAssertTrue(Analytics.isEnabled)
    }

    func test_is_enabled_reflects_stored_opt_out() {
        Analytics.defaults.set(false, forKey: Analytics.enabledKey)
        XCTAssertFalse(Analytics.isEnabled)
    }

    func test_start_passes_stored_setting_to_provider() {
        Analytics.defaults.set(false, forKey: Analytics.enabledKey)
        Analytics.start()
        XCTAssertEqual(spy.startedWith, [false])
    }

    func test_refresh_forwards_current_setting_to_provider() {
        Analytics.defaults.set(false, forKey: Analytics.enabledKey)
        Analytics.refresh()
        Analytics.defaults.set(true, forKey: Analytics.enabledKey)
        Analytics.refresh()
        XCTAssertEqual(spy.enabledChanges, [false, true])
    }

    func test_custom_event_routes_to_one_sentry_counter() {
        Analytics.viewModeChanged(.list)

        XCTAssertEqual(spy.metricKeys, [Analytics.metricKey])
        XCTAssertEqual(spy.metricValues, [1])
        XCTAssertEqual(spy.metricAttributes.first?["event.name"], .string("View.modeChanged"))
        XCTAssertEqual(spy.metricAttributes.first?["schema.version"], .integer(1))
        XCTAssertTrue(spy.startedWith.isEmpty)
    }

    // MARK: - Cask action events

    func test_adopt_completion_and_greedy_toggle_send_signals() {
        Analytics.caskActionCompleted(.adopting, token: "chrome")
        Analytics.greedyUpdatesChanged(true)

        XCTAssertEqual(spy.signals[0].name, "Cask.adopted")
        XCTAssertEqual(spy.signals[0].parameters["cask"], "chrome")
        XCTAssertEqual(spy.signals[1].name, "Filter.greedyChanged")
        XCTAssertEqual(spy.signals[1].parameters["enabled"], "true")
    }

    func test_cask_action_completed_maps_actions_to_past_tense_signals() {
        Analytics.caskActionCompleted(.installing, token: "firefox")
        Analytics.caskActionCompleted(.uninstalling, token: "firefox")
        Analytics.caskActionCompleted(.updating, token: "firefox")

        XCTAssertEqual(
            spy.signals.map(\.name),
            ["Cask.installed", "Cask.uninstalled", "Cask.updated"]
        )
        XCTAssertEqual(lastSignal?.parameters, ["cask": "firefox", "origin": "individual"])
    }

    func test_cask_action_started_breadcrumbs_without_signaling() {
        let crashSpy = SpyCrashReporterProvider()
        let originalCrash = CrashReporter.provider
        CrashReporter.provider = crashSpy
        defer { CrashReporter.provider = originalCrash }

        Analytics.caskActionStarted(.updating, token: "zoom", origin: .updateAll)

        XCTAssertTrue(spy.signals.isEmpty)
        XCTAssertEqual(crashSpy.breadcrumbs.last?.message, "Cask.actionStarted")
        XCTAssertEqual(crashSpy.breadcrumbs.last?.data, [
            "action": "update",
            "cask": "zoom",
            "origin": "updateAll"
        ])
    }

    func test_cask_action_completed_ignores_app_launches() {
        Analytics.caskActionCompleted(.opening, token: "firefox")
        XCTAssertTrue(spy.signals.isEmpty)
    }

    func test_cask_action_failed_omits_failure_class_when_unavailable() {
        Analytics.caskActionFailed(.updating, token: "iterm2")
        XCTAssertEqual(lastSignal?.name, "Cask.actionFailed")
        XCTAssertEqual(lastSignal?.parameters, [
            "action": "update",
            "cask": "iterm2",
            "origin": "individual"
        ])
    }

    func test_cask_action_failed_includes_failure_class_when_provided() {
        Analytics.caskActionFailed(
            .installing,
            token: "gimp",
            failureKind: .homebrewRuntimeIncompatible
        )

        XCTAssertEqual(lastSignal?.parameters, [
            "action": "install",
            "cask": "gimp",
            "failureClass": "homebrew-runtime-incompatible",
            "origin": "individual"
        ])
    }

    func test_cask_action_recovered_records_repair_postcondition() {
        Analytics.caskActionRecovered(.uninstalling, token: "zed", origin: .repair)

        XCTAssertEqual(lastSignal?.name, "Cask.actionRecovered")
        XCTAssertEqual(lastSignal?.parameters, [
            "action": "uninstall",
            "cask": "zed",
            "origin": "repair"
        ])
    }

    func test_cask_action_failed_tracks_missing_app_launches() {
        Analytics.caskActionFailed(
            .opening,
            token: "firefox",
            failureKind: .appBundleNotFound
        )
        XCTAssertEqual(lastSignal?.parameters, [
            "action": "open",
            "cask": "firefox",
            "failureClass": "app-bundle-not-found",
            "origin": "individual"
        ])
    }

    func test_cask_action_events_ignore_queued_state() {
        Analytics.caskActionStarted(.queued, token: "firefox", origin: .updateAll)
        Analytics.caskActionCompleted(.queued, token: "firefox")
        Analytics.caskActionFailed(.queued, token: "firefox")
        XCTAssertTrue(spy.signals.isEmpty)
    }

    func test_update_all_tapped_sends_queue_size() {
        Analytics.updateAllTapped(count: 3)
        XCTAssertEqual(lastSignal?.name, "Cask.updateAllTapped")
        XCTAssertEqual(lastSignal?.parameters, ["count": "3"])
    }

    func test_telemetry_provider_keeps_automatic_lifecycle_and_honors_consent() {
        var configs: [TelemetryDeck.Config] = []
        let provider = TelemetryDeckProvider(appID: { "test-app-id" }, initialize: { configs.append($0) })

        provider.start(enabled: true)
        provider.setEnabled(false)

        XCTAssertEqual(configs.count, 1)
        XCTAssertTrue(configs[0].analyticsDisabled)
        XCTAssertTrue(configs[0].sendNewSessionBeganSignal)
        XCTAssertTrue(configs[0].sessionStatsEnabled)
    }

    func test_opted_out_launch_never_initializes_telemetry_until_opt_in() {
        var configs: [TelemetryDeck.Config] = []
        Analytics.provider = TelemetryDeckProvider(appID: { "test-app-id" }, initialize: { configs.append($0) })
        Analytics.defaults.set(false, forKey: Analytics.enabledKey)

        Analytics.start()
        Analytics.refresh()
        XCTAssertTrue(configs.isEmpty)

        Analytics.defaults.set(true, forKey: Analytics.enabledKey)
        Analytics.refresh()
        Analytics.defaults.set(false, forKey: Analytics.enabledKey)
        Analytics.refresh()

        XCTAssertEqual(configs.count, 1)
        XCTAssertTrue(configs[0].analyticsDisabled)
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

    func test_page_opened_signals_once_per_page_and_breadcrumbs_repeats() {
        let crashSpy = SpyCrashReporterProvider()
        let originalCrash = CrashReporter.provider
        CrashReporter.provider = crashSpy
        defer { CrashReporter.provider = originalCrash }

        Analytics.pageOpened(.discover(.browse))
        Analytics.pageOpened(.library(.installed))
        Analytics.pageOpened(.discover(.browse))

        XCTAssertEqual(spy.signals.map(\.name), ["Page.opened", "Page.opened"])
        XCTAssertEqual(
            spy.signals.map(\.parameters),
            [["page": "browse"], ["page": "installed"]]
        )
        XCTAssertEqual(crashSpy.breadcrumbs.count, 3)
    }

    func test_page_opened_maps_utility_pages() {
        Analytics.pageOpened(.shelfSetup)
        XCTAssertEqual(lastSignal?.parameters, ["page": "shelfSetup"])

        Analytics.pageOpened(.maintenance)
        XCTAssertEqual(lastSignal?.parameters, ["page": "maintenance"])
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

    func test_search_performed_counts_results_without_search_text() {
        Analytics.searchPerformed(results: 3)
        XCTAssertEqual(lastSignal?.name, "Search.performed")
        XCTAssertEqual(lastSignal?.parameters, ["results": "3"])
    }

    // MARK: - Filters, view mode & settings

    func test_filter_and_settings_event_names_and_parameters() {
        Analytics.sortChanged(.nameAZ)
        Analytics.topChartsPeriodChanged(.days90)
        Analytics.recentWindowChanged(.days30)
        Analytics.viewModeChanged(.list)
        Analytics.themeChanged("Dark")
        Analytics.styleChanged(.native)
        Analytics.analyticsReEnabled()

        XCTAssertEqual(spy.signals.map(\.name), [
            "Filter.sortChanged",
            "Filter.periodChanged",
            "Filter.windowChanged",
            "View.modeChanged",
            "Settings.themeChanged", "Settings.styleChanged",
            "Settings.analyticsEnabled"
        ])
        XCTAssertEqual(spy.signals.map(\.parameters), [
            ["option": "Name (A→Z)"],
            ["period": "90d"],
            ["window": "30d"],
            ["mode": "list"],
            ["theme": "Dark"],
            ["style": "native"],
            [:]
        ])
    }

    // MARK: - Launch cards

    func test_launch_card_event_names_and_parameters() {
        Analytics.launchCardShown(.welcome)
        Analytics.welcomeLookConfirmed(.classic)
        Analytics.launchCardDismissed(.welcome, page: 3, style: .classic)
        Analytics.launchCardShown(.whatsNew)
        Analytics.launchCardDismissed(.whatsNew, style: .native)

        XCTAssertEqual(spy.signals.map(\.name), [
            "LaunchCard.shown", "LaunchCard.lookConfirmed", "LaunchCard.dismissed",
            "LaunchCard.shown", "LaunchCard.dismissed"
        ])
        XCTAssertEqual(spy.signals.map(\.parameters), [
            ["kind": "welcome"],
            ["style": "classic"],
            ["kind": "welcome", "page": "3", "style": "classic"],
            ["kind": "whatsNew"],
            ["kind": "whatsNew", "style": "native"]
        ])
    }

    func test_welcome_look_confirmation_sends_once_per_distinct_style() {
        var confirmation = WelcomeLookConfirmation()
        confirmation.confirm(.native)
        confirmation.confirm(.native)
        confirmation.confirm(.classic)

        XCTAssertEqual(spy.signals.map(\.name), ["LaunchCard.lookConfirmed", "LaunchCard.lookConfirmed"])
        XCTAssertEqual(spy.signals.map(\.parameters), [["style": "native"], ["style": "classic"]])
    }

    // MARK: - Crash-report breadcrumbs

    func test_send_records_breadcrumb_regardless_of_analytics_consent() {
        let crashSpy = SpyCrashReporterProvider()
        let originalCrash = CrashReporter.provider
        CrashReporter.provider = crashSpy
        defer { CrashReporter.provider = originalCrash }
        Analytics.defaults.set(false, forKey: Analytics.enabledKey)

        Analytics.send("Page.opened", parameters: ["page": "installed"])

        XCTAssertTrue(spy.signals.isEmpty)
        XCTAssertEqual(crashSpy.breadcrumbs.last?.message, "Page.opened")
        XCTAssertEqual(crashSpy.breadcrumbs.last?.data, ["page": "installed"])
    }

    func test_send_skips_breadcrumb_when_crash_reporting_is_off() {
        let crashSpy = SpyCrashReporterProvider()
        let originalCrash = CrashReporter.provider
        CrashReporter.provider = crashSpy
        defer {
            CrashReporter.provider = originalCrash
            CrashReporter.defaults.removeObject(forKey: CrashReporter.enabledKey)
        }
        CrashReporter.defaults.set(false, forKey: CrashReporter.enabledKey)

        Analytics.send("Page.opened")

        XCTAssertTrue(crashSpy.breadcrumbs.isEmpty)
    }
}
