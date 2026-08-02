//
//  CaskCatalogViewModelTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/07/2026.
//

@testable import CaskHub
import XCTest

final class CaskCatalogViewModelTests: XCTestCase {
    // MARK: Fetching

    @MainActor
    func test_fetch_casks_excludes_deprecated_disabled_versioned_and_font_casks() async {
        let (vm, _) = await makeSUT(casks: [
            makeCask("firefox"),
            Cask.preview(token: "legacy-app", deprecated: true),
            Cask.preview(token: "dead-app", disabled: true),
            makeCask("node@18"),
            makeCask("font-fira-code")
        ])

        XCTAssertEqual(vm.filteredCasks.map(\.token), ["firefox"])
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    @MainActor
    func test_fetch_casks_sets_error_message_and_clears_loading_on_failure() async {
        let api = MockBrewAPIClient()
        api.casksError = URLError(.notConnectedToInternet)
        let vm = makeViewModel(api: api)

        await vm.fetchCasks()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.filteredCasks.isEmpty)
    }

    @MainActor
    func test_fetch_casks_survives_analytics_failure() async {
        let api = MockBrewAPIClient()
        api.casks = [makeCask("firefox")]
        api.analyticsError = URLError(.timedOut)
        let vm = makeViewModel(api: api)

        await vm.fetchCasks()

        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["firefox"])
        XCTAssertNil(vm.formattedDownloads(for: "firefox"))
    }

    // MARK: Search

    @MainActor
    func test_filtered_casks_matches_search_in_name_token_and_description() async {
        let (vm, _) = await makeSUT(casks: [
            makeCask("visual-studio-code", name: "Visual Studio Code"),
            makeCask("firefox", name: "Firefox", desc: "Web browser"),
            makeCask("slack", name: "Slack")
        ])

        vm.searchText = "browser"
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["firefox"])

        vm.searchText = "studio"
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["visual-studio-code"])

        vm.searchText = "SLACK"
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["slack"])

        vm.searchText = "oxweb"
        XCTAssertTrue(vm.filteredCasks.isEmpty, "query must not match across field boundaries")

        vm.searchText = ""
        XCTAssertEqual(vm.filteredCasks.count, 3)
    }

    @MainActor
    func test_search_projection_debounces_typing_and_clears_instantly() async throws {
        let (vm, _) = await makeSUT(casks: [
            makeCask("firefox", name: "Firefox", desc: "Web browser")
        ])
        vm.searchDebounceInterval = .milliseconds(50)

        vm.searchText = "b"
        vm.searchText = "br"
        vm.searchText = "browser"
        XCTAssertEqual(vm.appliedSearchText, "")

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(vm.appliedSearchText, "browser")
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["firefox"])

        vm.searchText = ""
        XCTAssertEqual(vm.appliedSearchText, "")
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["firefox"])
    }

    // MARK: Sidebar filters

    @MainActor
    func test_filtered_casks_for_category_page_includes_secondary_assignments() async {
        let categories = seededCategories(
            [
                "firefox": TokenCategoryMapping(primary: "browsers", secondary: []),
                "slack": TokenCategoryMapping(primary: "productivity", secondary: ["browsers"]),
                "iterm2": TokenCategoryMapping(primary: "developer-tools", secondary: [])
            ],
            categories: [
                "browsers": CategoryDefinition(displayName: "Browsers", icon: "globe"),
                "productivity": CategoryDefinition(displayName: "Productivity", icon: "checklist"),
                "developer-tools": CategoryDefinition(displayName: "Developer Tools", icon: "hammer")
            ]
        )
        let (vm, _) = await makeSUT(
            casks: [makeCask("firefox"), makeCask("slack"), makeCask("iterm2")],
            categories: categories
        )

        vm.selectedSidebar = .category("browsers")

        XCTAssertEqual(Set(vm.filteredCasks.map(\.token)), ["firefox", "slack"])
        XCTAssertEqual(vm.categoryCounts["browsers"], 2)
        XCTAssertEqual(vm.categoryCounts["developer-tools"], 1)
    }

    @MainActor
    func test_installed_and_updates_pages_reflect_local_state() async {
        // Scratch defaults: the host app's real prefs may have greedyUpdates on.
        let local = LocalHomebrewService(defaults: makeScratchDefaults("installed-updates"))
        updateInstallationSnapshot(of: local) {
            $0.installedCasks = [
                "firefox": installation("firefox", version: "1.0"),
                "slack": installation("slack", version: "2.0"),
                "chrome": installation("chrome", version: "1.0")
            ]
        }
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("firefox", version: "2.0"),
                makeCask("slack", version: "2.0"),
                Cask.preview(token: "chrome", version: "3.0", autoUpdates: true),
                makeCask("iterm2", version: "9.9")
            ],
            localHomebrew: local
        )

        vm.selectedSidebar = .library(.installed)
        XCTAssertEqual(Set(vm.filteredCasks.map(\.token)), ["firefox", "slack", "chrome"])

        vm.selectedSidebar = .library(.updates)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["firefox"])
        XCTAssertEqual(vm.updatableCasks.map(\.token), ["firefox"])
        XCTAssertEqual(vm.updatesCount, 1)
    }

    @MainActor
    func test_recently_added_page_respects_window() async {
        let recent = RecentlyAddedService()
        recent.addedDates = [
            "new-app": dateString(daysAgo: 5),
            "old-app": dateString(daysAgo: 100)
        ]
        let (vm, _) = await makeSUT(
            casks: [makeCask("new-app"), makeCask("old-app"), makeCask("undated-app")],
            recentlyAdded: recent
        )

        vm.selectedSidebar = .discover(.recentlyAdded)

        XCTAssertEqual(vm.filteredCasks.map(\.token), ["undated-app", "new-app"])
        vm.selectRecentlyAddedWindow(.days90)
        XCTAssertEqual(Set(vm.filteredCasks.map(\.token)), ["undated-app", "new-app"])
    }

    @MainActor
    func test_background_fetch_stays_silent_when_catalog_present() async {
        let (vm, api) = await makeSUT(casks: [makeCask("first")])

        api.casks = [makeCask("first"), makeCask("second")]
        await vm.fetchCasks()
        XCTAssertEqual(vm.casks.count, 2)

        api.casksError = URLError(.notConnectedToInternet)
        await vm.fetchCasks()
        XCTAssertEqual(vm.casks.count, 2)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    @MainActor
    func test_refresh_if_stale_throttles_within_max_age_and_before_first_load() async {
        let (vm, api) = await makeSUT(casks: [makeCask("first")])
        api.casks = [makeCask("first"), makeCask("second")]

        await vm.refreshIfStale(maxAge: 0)
        XCTAssertEqual(vm.casks.count, 1)

        vm.lastLoadedAt = .now
        await vm.refreshIfStale()
        XCTAssertEqual(vm.casks.count, 1)
    }

    @MainActor
    func test_unmined_tokens_count_as_recently_added_until_dates_refresh() async {
        let recent = RecentlyAddedService()
        recent.addedDates = ["old-app": dateString(daysAgo: 100)]
        let (vm, _) = await makeSUT(
            casks: [makeCask("old-app"), makeCask("brand-new")],
            recentlyAdded: recent
        )

        vm.selectedSidebar = .discover(.recentlyAdded)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["brand-new"])

        let shelf = vm.browseSections.first { $0.title == "Recently Added" }
        XCTAssertEqual(shelf?.casks.map(\.token), ["brand-new"])

        recent.addedDates["brand-new"] = dateString(daysAgo: 1)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["brand-new"])
    }

    // MARK: Browse sections

    @MainActor
    func test_browse_sections_cap_shelf_size_skip_other_and_drop_empty_shelves() async {
        let browserTokens = (0 ..< 10).map { "browser-\($0)" }
        var mappings = Dictionary(uniqueKeysWithValues: browserTokens.map {
            ($0, TokenCategoryMapping(primary: "browsers", secondary: []))
        })
        mappings["misc-app"] = TokenCategoryMapping(primary: "other", secondary: [])
        let categories = seededCategories(mappings, categories: [
            "browsers": CategoryDefinition(displayName: "Browsers", icon: "globe"),
            "developer-tools": CategoryDefinition(displayName: "Developer Tools", icon: "hammer"),
            "other": CategoryDefinition(displayName: "Other", icon: "square")
        ])
        let (vm, _) = await makeSUT(
            casks: (browserTokens + ["misc-app"]).map { makeCask($0) },
            analytics: browserTokens.enumerated().map { ($0.element, "\(($0.offset + 1) * 100)") },
            categories: categories
        )

        let sections = vm.browseSections

        XCTAssertEqual(sections.map(\.title), ["Most Popular", "Browsers"])
        XCTAssertEqual(sections[0].destination, .discover(.topCharts))
        XCTAssertEqual(sections[1].destination, .category("browsers"))
        XCTAssertEqual(sections[0].casks.count, 8)
        XCTAssertEqual(sections[1].casks.first?.token, "browser-9")
    }

    @MainActor
    func test_browse_recently_added_shelf_orders_by_newest_not_downloads() async {
        let recent = RecentlyAddedService()
        recent.addedDates = [
            "old-hit": dateString(daysAgo: 20),
            "new-app": dateString(daysAgo: 1)
        ]
        let (vm, _) = await makeSUT(
            casks: [makeCask("old-hit"), makeCask("new-app")],
            analytics: [("old-hit", "1000"), ("new-app", "10")],
            recentlyAdded: recent
        )

        let shelf = vm.browseSections.first { $0.title == "Recently Added" }
        XCTAssertEqual(shelf?.casks.map(\.token), ["new-app", "old-hit"])
    }

    // MARK: Analytics

    @MainActor
    func test_formatted_downloads_abbreviates_thousands_and_millions() async {
        let (vm, _) = await makeSUT(
            casks: [makeCask("big"), makeCask("mid"), makeCask("small"), makeCask("zero")],
            analytics: [("big", "2,500,000"), ("mid", "3,400"), ("small", "999"), ("zero", "0")]
        )

        XCTAssertEqual(vm.formattedDownloads(for: "big"), "2.5M")
        XCTAssertEqual(vm.formattedDownloads(for: "mid"), "3.4K")
        XCTAssertEqual(vm.formattedDownloads(for: "small"), "999")
        XCTAssertNil(vm.formattedDownloads(for: "zero"))
        XCTAssertNil(vm.formattedDownloads(for: "unknown"))
    }

    @MainActor
    func test_duplicate_analytics_entries_keep_the_max_count() async {
        let (vm, _) = await makeSUT(
            casks: [makeCask("firefox")],
            analytics: [("firefox", "100"), ("firefox", "250")]
        )

        XCTAssertEqual(vm.formattedDownloads(for: "firefox"), "250")
    }

    @MainActor
    func test_select_analytics_period_fetches_each_period_once() async {
        let (vm, api) = await makeSUT()
        XCTAssertEqual(api.analyticsFetches, [.days365])

        await vm.selectAnalyticsPeriod(.days30)
        XCTAssertEqual(api.analyticsFetches, [.days365, .days30])
        XCTAssertEqual(vm.analyticsPeriod, .days30)

        await vm.selectAnalyticsPeriod(.days30)
        XCTAssertEqual(api.analyticsFetches, [.days365, .days30])
    }

    @MainActor
    func test_failed_period_selection_keeps_loaded_period_and_never_relabels_annual_data() async {
        let defaults = makeScratchDefaults()
        let api = MockBrewAPIClient()
        api.casks = [makeCask("firefox")]
        api.analyticsResponses[.days365] = analyticsResponse([("firefox", "100")])
        let vm = makeViewModel(api: api, defaults: defaults)
        await vm.fetchCasks()
        vm.selectedSidebar = .discover(.topCharts)
        api.analyticsError = URLError(.timedOut)

        await vm.selectAnalyticsPeriod(.days30)

        XCTAssertEqual(vm.analyticsPeriod, .days365)
        XCTAssertEqual(vm.formattedDownloads(for: "firefox"), "100")
        XCTAssertEqual(defaults.string(forKey: "analyticsPeriod"), AnalyticsPeriod.days365.rawValue)
    }

    @MainActor
    func test_persisted_unloaded_period_does_not_fall_back_to_annual_counts() async {
        let defaults = makeScratchDefaults()
        defaults.set(AnalyticsPeriod.days30.rawValue, forKey: "analyticsPeriod")
        let api = MockBrewAPIClient()
        api.casks = [makeCask("firefox")]
        api.analyticsResponses[.days365] = analyticsResponse([("firefox", "100")])
        let vm = makeViewModel(api: api, defaults: defaults)
        await vm.fetchCasks()
        vm.selectedSidebar = .discover(.topCharts)

        XCTAssertEqual(vm.analyticsPeriod, .days30)
        XCTAssertNil(vm.formattedDownloads(for: "firefox"))
    }

    @MainActor
    func test_recently_added_loads_bundled_offline_snapshot() {
        let recent = RecentlyAddedService()

        recent.loadBundledDates()

        XCTAssertFalse(recent.addedDates.isEmpty)
        XCTAssertFalse(recent.generatedDate.isEmpty)
    }

    @MainActor
    func test_top_charts_uses_selected_period_while_other_pages_stay_on_year() async {
        let (vm, api) = await makeSUT(
            casks: [makeCask("firefox")],
            analytics: [("firefox", "100")]
        )
        api.analyticsResponses[.days30] = analyticsResponse([("firefox", "5,000")])

        vm.selectedSidebar = .discover(.topCharts)
        await vm.selectAnalyticsPeriod(.days30)
        XCTAssertEqual(vm.formattedDownloads(for: "firefox"), "5K")

        vm.selectedSidebar = .discover(.browse)
        XCTAssertEqual(vm.formattedDownloads(for: "firefox"), "100")
    }

    // MARK: - Crash reporting

    @MainActor
    func test_fetch_failure_is_captured_and_finishes_span_with_error() async {
        let crashSpy = SpyCrashReporterProvider()
        let originalCrash = CrashReporter.provider
        CrashReporter.provider = crashSpy
        CrashReporter.isRunningTests = false
        defer {
            CrashReporter.provider = originalCrash
            CrashReporter.isRunningTests = CrashReporter.detectsTestRun
        }
        CrashReporter.captureCounts = [:]

        let api = MockBrewAPIClient()
        // Transport failures are deliberately ignored; malformed server responses are reportable.
        api.casksError = URLError(.badServerResponse)
        let vm = makeViewModel(api: api)

        await vm.fetchCasks()

        XCTAssertEqual(crashSpy.capturedErrors.count, 1)
        XCTAssertEqual(crashSpy.spans.last?.name, "catalog.fetch")
        XCTAssertEqual(crashSpy.spans.last?.operation, "http")
        XCTAssertNotNil(crashSpy.spans.last?.span.finishedError)
    }

    // MARK: - Persistence

    @MainActor
    func test_selected_analytics_period_and_recent_window_survive_relaunch() async {
        let defaults = makeScratchDefaults()
        let vm = makeViewModel(api: MockBrewAPIClient(), defaults: defaults)

        await vm.selectAnalyticsPeriod(.days30)
        vm.selectRecentlyAddedWindow(.days90)

        let relaunched = makeViewModel(api: MockBrewAPIClient(), defaults: defaults)
        XCTAssertEqual(relaunched.analyticsPeriod, .days30)
        XCTAssertEqual(relaunched.recentlyAddedWindow, .days90)
    }

    @MainActor
    func test_defaults_apply_when_nothing_persisted_or_value_is_garbage() {
        let defaults = makeScratchDefaults()

        let fresh = makeViewModel(api: MockBrewAPIClient(), defaults: defaults)
        XCTAssertEqual(fresh.analyticsPeriod, .days365)
        XCTAssertEqual(fresh.recentlyAddedWindow, .days30)

        defaults.set("14d", forKey: "analyticsPeriod")
        defaults.set(45, forKey: "recentlyAddedWindow")
        let garbled = makeViewModel(api: MockBrewAPIClient(), defaults: defaults)
        XCTAssertEqual(garbled.analyticsPeriod, .days365)
        XCTAssertEqual(garbled.recentlyAddedWindow, .days30)
    }
}
