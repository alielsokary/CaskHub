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

private final class SpyAnalyticsProvider: AnalyticsProvider, SentryMetricsApiProtocol {
    var startedWith: [Bool] = []
    var enabledChanges: [Bool] = []
    var signals: [(name: String, parameters: [String: String])] = []
    var metricKeys: [String] = []
    var metricValues: [UInt] = []
    var metricAttributes: [[String: SentryAttributeContent]] = []

    func start(enabled: Bool) { startedWith.append(enabled) }
    func setEnabled(_ enabled: Bool) { enabledChanges.append(enabled) }

    func count(
        key: String,
        value: UInt,
        attributes: [String: SentryAttributeValue]
    ) {
        let attributes = attributes.mapValues { $0.asSentryAttributeContent }
        metricKeys.append(key)
        metricValues.append(value)
        metricAttributes.append(attributes)

        guard case let .string(name)? = attributes["event.name"] else { return }
        let parameters = attributes.reduce(into: [String: String]()) { result, attribute in
            guard attribute.key.hasPrefix("event."), attribute.key != "event.name",
                  case let .string(value) = attribute.value
            else { return }
            result[String(attribute.key.dropFirst("event.".count))] = value
        }
        signals.append((name, parameters))
    }

    func distribution(
        key _: String,
        value _: Double,
        unit _: SentryUnit?,
        attributes _: [String: SentryAttributeValue]
    ) {}

    func gauge(
        key _: String,
        value _: Double,
        unit _: SentryUnit?,
        attributes _: [String: SentryAttributeValue]
    ) {}
}

final class AnalyticsTests: XCTestCase {
    private var spy: SpyAnalyticsProvider!
    private var originalProvider: AnalyticsProvider!
    private var originalMetrics: SentryMetricsApiProtocol!
    private var originalAnalyticsDefaults: UserDefaults!
    private var originalCrashDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        spy = SpyAnalyticsProvider()
        originalProvider = Analytics.provider
        originalMetrics = Analytics.metrics
        originalAnalyticsDefaults = Analytics.defaults
        originalCrashDefaults = CrashReporter.defaults
        Analytics.provider = spy
        Analytics.metrics = spy
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

    @MainActor
    func test_failed_service_mutation_forwards_its_classification() async {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [BrewProcessResult(
            exitCode: 1,
            output: "Error: Cask 'gimp' definition is invalid: invalid "
                + "'command_wrapper' stanza: Unknown key: :executable"
        )]
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("classified-analytics")
        ) {
            $0.fileManager = NoFilesFileManager()
            $0.processRunner = runner
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
        }

        try? await service.install(token: "gimp")

        XCTAssertEqual(lastSignal?.name, "Cask.actionFailed")
        XCTAssertEqual(lastSignal?.parameters["failureClass"], "homebrew-runtime-incompatible")
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

    func test_cask_action_failed_ignores_app_launches() {
        Analytics.caskActionFailed(.opening, token: "firefox")
        XCTAssertTrue(spy.signals.isEmpty)
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
        var config: TelemetryDeck.Config?
        let provider = TelemetryDeckProvider(
            appID: { "test-app-id" },
            initialize: { config = $0 }
        )

        provider.start(enabled: false)

        XCTAssertTrue(config?.analyticsDisabled == true)
        XCTAssertTrue(config?.sendNewSessionBeganSignal == true)
        XCTAssertTrue(config?.sessionStatsEnabled == true)

        provider.setEnabled(true)

        XCTAssertTrue(config?.analyticsDisabled == false)
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
