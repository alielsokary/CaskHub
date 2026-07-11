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
        let api = MockBrewAPIClient()
        api.casks = [
            makeCask("firefox"),
            makeCask("legacy-app", deprecated: true),
            makeCask("dead-app", disabled: true),
            makeCask("node@18"),
            makeCask("font-fira-code")
        ]
        let vm = makeViewModel(api: api)

        await vm.fetchCasks()

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
        let api = MockBrewAPIClient()
        api.casks = [
            makeCask("visual-studio-code", name: "Visual Studio Code"),
            makeCask("firefox", name: "Firefox", desc: "Web browser"),
            makeCask("slack", name: "Slack")
        ]
        let vm = makeViewModel(api: api)
        await vm.fetchCasks()

        vm.searchText = "browser" // description match
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["firefox"])

        vm.searchText = "studio" // token + name match
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["visual-studio-code"])

        vm.searchText = "SLACK" // case-insensitive
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["slack"])

        vm.searchText = ""
        XCTAssertEqual(vm.filteredCasks.count, 3)
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
        let api = MockBrewAPIClient()
        api.casks = [makeCask("firefox"), makeCask("slack"), makeCask("iterm2")]
        let vm = makeViewModel(api: api, categories: categories)
        await vm.fetchCasks()

        vm.selectedSidebar = .category("browsers")

        XCTAssertEqual(Set(vm.filteredCasks.map(\.token)), ["firefox", "slack"])
        XCTAssertEqual(vm.categoryCounts["browsers"], 2)
        XCTAssertEqual(vm.categoryCounts["developer-tools"], 1)
    }

    @MainActor
    func test_installed_and_updates_pages_reflect_local_state() async {
        let local = LocalHomebrewService()
        local.installedCasks = [
            "firefox": installation("firefox", version: "1.0"), // outdated
            "slack": installation("slack", version: "2.0"),     // current
            "chrome": installation("chrome", version: "1.0")    // outdated but auto-updates
        ]
        let api = MockBrewAPIClient()
        api.casks = [
            makeCask("firefox", version: "2.0"),
            makeCask("slack", version: "2.0"),
            makeCask("chrome", version: "3.0", autoUpdates: true),
            makeCask("iterm2", version: "9.9")
        ]
        let vm = makeViewModel(api: api, localHomebrew: local)
        await vm.fetchCasks()

        vm.selectedSidebar = .library(.installed)
        XCTAssertEqual(Set(vm.filteredCasks.map(\.token)), ["firefox", "slack", "chrome"])

        vm.selectedSidebar = .library(.updates)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["firefox"])
        XCTAssertEqual(vm.updatesCount, 1)
    }

    @MainActor
    func test_recently_added_page_respects_window() async {
        let recent = RecentlyAddedService()
        recent.addedDates = [
            "new-app": dateString(daysAgo: 5),
            "old-app": dateString(daysAgo: 100)
        ]
        let api = MockBrewAPIClient()
        api.casks = [makeCask("new-app"), makeCask("old-app"), makeCask("undated-app")]
        let vm = makeViewModel(api: api, recentlyAdded: recent)
        await vm.fetchCasks()

        vm.selectedSidebar = .discover(.recentlyAdded)

        XCTAssertEqual(vm.filteredCasks.map(\.token), ["new-app"]) // default 30d window
        vm.recentlyAddedWindow = .days90
        XCTAssertEqual(Set(vm.filteredCasks.map(\.token)), ["new-app"])
    }

    // MARK: Sorting

    @MainActor
    func test_sort_options_order_by_downloads_name_and_added_date() async {
        let recent = RecentlyAddedService()
        recent.addedDates = [
            "bravo": dateString(daysAgo: 1),
            "alpha": dateString(daysAgo: 50)
        ]
        let api = MockBrewAPIClient()
        api.casks = [makeCask("alpha"), makeCask("charlie"), makeCask("bravo")]
        api.analyticsResponses[.days365] = analyticsResponse([
            ("bravo", "300"), ("alpha", "200"), ("charlie", "100")
        ])
        let vm = makeViewModel(api: api, recentlyAdded: recent)
        await vm.fetchCasks()

        vm.sortOption = .mostPopular
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["bravo", "alpha", "charlie"])

        vm.sortOption = .nameAZ
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["alpha", "bravo", "charlie"])

        vm.sortOption = .nameZA
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["charlie", "bravo", "alpha"])

        vm.sortOption = .newest // undated casks sink to the end
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["bravo", "alpha", "charlie"])

        vm.sortOption = .oldest
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["alpha", "bravo", "charlie"])
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
        let api = MockBrewAPIClient()
        api.casks = (browserTokens + ["misc-app"]).map { makeCask($0) }
        api.analyticsResponses[.days365] = analyticsResponse(
            browserTokens.enumerated().map { ($0.element, "\(($0.offset + 1) * 100)") }
        )
        let vm = makeViewModel(api: api, categories: categories)
        await vm.fetchCasks()

        let sections = vm.browseSections

        // "Recently Added" (no dates), "Developer Tools" (no casks) and
        // "Other" (always) are dropped.
        XCTAssertEqual(sections.map(\.title), ["Most Popular", "Browsers"])
        XCTAssertEqual(sections[0].destination, .discover(.topCharts))
        XCTAssertEqual(sections[1].destination, .category("browsers"))
        XCTAssertEqual(sections[0].casks.count, 8) // two grid rows max
        XCTAssertEqual(sections[1].casks.first?.token, "browser-9") // top downloads first
    }

    // MARK: Analytics

    @MainActor
    func test_formatted_downloads_abbreviates_thousands_and_millions() async {
        let api = MockBrewAPIClient()
        api.casks = [makeCask("big"), makeCask("mid"), makeCask("small"), makeCask("zero")]
        api.analyticsResponses[.days365] = analyticsResponse([
            ("big", "2,500,000"), ("mid", "3,400"), ("small", "999"), ("zero", "0")
        ])
        let vm = makeViewModel(api: api)
        await vm.fetchCasks()

        XCTAssertEqual(vm.formattedDownloads(for: "big"), "2.5M")
        XCTAssertEqual(vm.formattedDownloads(for: "mid"), "3.4K")
        XCTAssertEqual(vm.formattedDownloads(for: "small"), "999")
        XCTAssertNil(vm.formattedDownloads(for: "zero"))
        XCTAssertNil(vm.formattedDownloads(for: "unknown"))
    }

    @MainActor
    func test_duplicate_analytics_entries_keep_the_max_count() async {
        let api = MockBrewAPIClient()
        api.casks = [makeCask("firefox")]
        api.analyticsResponses[.days365] = analyticsResponse([
            ("firefox", "100"), ("firefox", "250")
        ])
        let vm = makeViewModel(api: api)
        await vm.fetchCasks()

        XCTAssertEqual(vm.formattedDownloads(for: "firefox"), "250")
    }

    @MainActor
    func test_select_analytics_period_fetches_each_period_once() async {
        let api = MockBrewAPIClient()
        let vm = makeViewModel(api: api)
        await vm.fetchCasks()
        XCTAssertEqual(api.analyticsFetches, [.days365])

        await vm.selectAnalyticsPeriod(.days30)
        XCTAssertEqual(api.analyticsFetches, [.days365, .days30])
        XCTAssertEqual(vm.analyticsPeriod, .days30)

        await vm.selectAnalyticsPeriod(.days30) // cached — no refetch
        XCTAssertEqual(api.analyticsFetches, [.days365, .days30])
    }

    @MainActor
    func test_top_charts_uses_selected_period_while_other_pages_stay_on_year() async {
        let api = MockBrewAPIClient()
        api.casks = [makeCask("firefox")]
        api.analyticsResponses[.days365] = analyticsResponse([("firefox", "100")])
        api.analyticsResponses[.days30] = analyticsResponse([("firefox", "5,000")])
        let vm = makeViewModel(api: api)
        await vm.fetchCasks()

        vm.selectedSidebar = .discover(.topCharts)
        await vm.selectAnalyticsPeriod(.days30)
        XCTAssertEqual(vm.formattedDownloads(for: "firefox"), "5.0K")

        vm.selectedSidebar = .discover(.browse)
        XCTAssertEqual(vm.formattedDownloads(for: "firefox"), "100")
    }
}
