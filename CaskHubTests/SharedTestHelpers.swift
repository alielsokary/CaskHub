//
//  SharedTestHelpers.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/07/2026.
//

@testable import CaskHub
import Foundation

// MARK: - Mock API

@MainActor
final class MockBrewAPIClient: BrewAPIClientProtocol {
    var casks: [Cask] = []
    var casksError: Error?
    var analyticsResponses: [AnalyticsPeriod: CaskAnalyticsResponse] = [:]
    var analyticsError: Error?
    private(set) var analyticsFetches: [AnalyticsPeriod] = []

    func fetchAllCasks() async throws -> [Cask] {
        if let casksError { throw casksError }
        return casks
    }

    func fetchAnalytics(period: AnalyticsPeriod) async throws -> CaskAnalyticsResponse {
        analyticsFetches.append(period)
        if let analyticsError { throw analyticsError }
        return analyticsResponses[period]
            ?? CaskAnalyticsResponse(category: "", totalItems: 0, startDate: "", endDate: "", totalCount: 0, items: [])
    }
}

// MARK: - Factories

@MainActor
func makeCask(
    _ token: String,
    name: String? = nil,
    desc: String? = nil,
    version: String = "1.0",
    deprecated: Bool = false,
    disabled: Bool = false,
    autoUpdates: Bool? = nil
) -> Cask {
    .preview(
        token: token,
        name: name,
        desc: desc,
        version: version,
        deprecated: deprecated,
        disabled: disabled,
        autoUpdates: autoUpdates
    )
}

@MainActor
func analyticsResponse(_ counts: [(String, String)]) -> CaskAnalyticsResponse {
    CaskAnalyticsResponse(
        category: "cask_install",
        totalItems: counts.count,
        startDate: "",
        endDate: "",
        totalCount: 0,
        items: counts.enumerated().map {
            CaskAnalyticsItem(number: $0.offset + 1, cask: $0.element.0, count: $0.element.1, percent: "0")
        }
    )
}

@MainActor
func installation(_ token: String, version: String) -> LocalCaskInstallation {
    LocalCaskInstallation(token: token, installedVersion: version, installedAt: nil, appBundleNames: [])
}

func dateString(daysAgo: Int) -> String {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
    return date.formatted(.iso8601.year().month().day())
}

@MainActor
func makeViewModel(
    api: MockBrewAPIClient,
    categories: CategoryService? = nil,
    recentlyAdded: RecentlyAddedService? = nil,
    localHomebrew: LocalHomebrewService? = nil,
    defaults: UserDefaults? = nil
) -> CaskCatalogViewModel {
    CaskCatalogViewModel(
        apiClient: api,
        categoryService: categories ?? CategoryService(),
        recentlyAdded: recentlyAdded ?? RecentlyAddedService(),
        localHomebrew: localHomebrew ?? LocalHomebrewService(),
        defaults: defaults ?? makeScratchDefaults("viewmodel-scratch")
    )
}

func makeScratchDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "test.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
func makeSUT(
    casks: [Cask] = [],
    analytics: [(String, String)]? = nil,
    categories: CategoryService? = nil,
    recentlyAdded: RecentlyAddedService? = nil,
    localHomebrew: LocalHomebrewService? = nil
) async -> (vm: CaskCatalogViewModel, api: MockBrewAPIClient) {
    let api = MockBrewAPIClient()
    api.casks = casks
    if let analytics {
        api.analyticsResponses[.days365] = analyticsResponse(analytics)
    }
    let vm = makeViewModel(
        api: api,
        categories: categories,
        recentlyAdded: recentlyAdded,
        localHomebrew: localHomebrew
    )
    await vm.fetchCasks()
    return (vm, api)
}

@MainActor
func seededCategories(_ tokenToCategory: [String: TokenCategoryMapping],
                      categories: [String: CategoryDefinition]) -> CategoryService {
    let service = CategoryService()
    service.applyData(CaskCategoryData(
        version: 1,
        generatedDate: "2026-07-11",
        releaseTag: nil,
        totalCasks: tokenToCategory.count,
        categories: categories,
        tokenToCategory: tokenToCategory,
        iconTokens: nil
    ))
    return service
}

// MARK: - Crash-reporting spies

final class SpyCrashSpan: CrashSpan {
    var finished = false
    var finishedError: Error?
    func finish() { finished = true }
    func finish(error: Error) {
        finished = true
        finishedError = error
    }
}

final class SpyCrashReporterProvider: CrashReporterProvider {
    struct SpanRecord {
        let name: String
        let operation: String
        let span: SpyCrashSpan
    }

    var startedWith: [Bool] = []
    var enabledChanges: [Bool] = []
    var capturedErrors: [Error] = []
    var breadcrumbs: [(message: String, data: [String: String])] = []
    var spans: [SpanRecord] = []

    func start(enabled: Bool) { startedWith.append(enabled) }
    func setEnabled(_ enabled: Bool) { enabledChanges.append(enabled) }
    func capture(_ error: Error) { capturedErrors.append(error) }
    func addBreadcrumb(_ message: String, data: [String: String]) {
        breadcrumbs.append((message, data))
    }
    func startSpan(name: String, operation: String) -> CrashSpan {
        let span = SpyCrashSpan()
        spans.append(SpanRecord(name: name, operation: operation, span: span))
        return span
    }
}
