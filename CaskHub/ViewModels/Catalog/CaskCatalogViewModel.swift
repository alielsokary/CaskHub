//
//  CaskCatalogViewModel.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation
import Observation

struct BrowseSection: Identifiable {
    let title: String
    let destination: SidebarSelection
    let casks: [Cask]

    var id: String {
        destination.id
    }
}

enum SortOption: String, CaseIterable, Identifiable {
    case mostPopular = "Most Popular"
    case nameAZ = "Name (A→Z)"
    case nameZA = "Name (Z→A)"
    case recentlyInstalled = "Recently Installed"
    case newest = "Newest"
    case oldest = "Oldest"

    var id: String {
        rawValue
    }

    static let standard: [SortOption] = [.mostPopular, .nameAZ, .nameZA]
    static let installed: [SortOption] = [.recentlyInstalled] + standard
}

@MainActor
@Observable
final class CaskCatalogViewModel {
    private(set) var casks: [Cask] = [] {
        didSet { catalogRevision &+= 1 }
    }
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var analyticsByPeriod: [AnalyticsPeriod: [String: Int]] = [:] {
        didSet { catalogRevision &+= 1 }
    }
    private(set) var analyticsPeriod: AnalyticsPeriod = .days365
    private var analyticsRequestID = UUID()
    private(set) var catalogRevision = 0
    var searchText = "" {
        didSet { scheduleSearchApply() }
    }
    /// Projection reads this instead of `searchText` so each keystroke echoes in
    /// the field immediately without re-filtering the full catalog on the MainActor.
    private(set) var appliedSearchText = "" {
        didSet { if oldValue != appliedSearchText { resetReveal() } }
    }
    static let revealChunk = 200
    private(set) var revealedCount = revealChunk

    func revealMore() {
        revealedCount += Self.revealChunk
    }

    private func resetReveal() {
        revealedCount = Self.revealChunk
    }
    @ObservationIgnored var searchDebounceInterval: Duration = .milliseconds(200)
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?

    @ObservationIgnored let libraryCache =
        MemoizedValue<CatalogLibraryCacheKey, CatalogLibrarySnapshot>()
    @ObservationIgnored let filteredCache =
        BoundedMemoizedValues<FilteredCatalogCacheKey, [Cask]>(capacity: 16)
    @ObservationIgnored let browseCache =
        MemoizedValue<BrowseCatalogCacheKey, [BrowseSection]>()
    @ObservationIgnored let searchKeysCache = MemoizedValue<Int, [String: String]>()
    @ObservationIgnored let nameRankCache = MemoizedValue<Int, [String: Int]>()

    private static let periodKey = "analyticsPeriod"
    private static let windowKey = "recentlyAddedWindow"

    var downloadCounts: [String: Int] {
        guard selectedSidebar == .discover(.topCharts) else {
            return analyticsByPeriod[.days365] ?? [:]
        }
        // Never label annual data as a shorter period while that period loads or fails.
        return analyticsByPeriod[analyticsPeriod] ?? [:]
    }

    var sortOption: SortOption = .mostPopular {
        didSet { if oldValue != sortOption { resetReveal() } }
    }
    var selectedSidebar: SidebarSelection = .discover(.browse) {
        didSet {
            guard oldValue != selectedSidebar else { return }
            resetReveal()
            switch selectedSidebar {
            case .library(.installed):
                sortOption = .recentlyInstalled
            case .library(.updates), .library(.adopt):
                sortOption = .nameAZ
            case .discover(.recentlyAdded):
                sortOption = .newest
            default:
                if !SortOption.standard.contains(sortOption) {
                    sortOption = .mostPopular
                }
            }
        }
    }

    private(set) var recentlyAddedWindow: RecentlyAddedWindow = .days30

    private let apiClient: BrewAPIClientProtocol
    let categoryService: CategoryService
    let recentlyAdded: RecentlyAddedService
    let localHomebrew: LocalHomebrewService
    private let defaults: UserDefaults

    init(
        apiClient: BrewAPIClientProtocol,
        categoryService: CategoryService,
        recentlyAdded: RecentlyAddedService,
        localHomebrew: LocalHomebrewService,
        defaults: UserDefaults = .standard
    ) {
        self.apiClient = apiClient
        self.categoryService = categoryService
        self.recentlyAdded = recentlyAdded
        self.localHomebrew = localHomebrew
        self.defaults = defaults

        if let raw = defaults.string(forKey: Self.periodKey),
           let period = AnalyticsPeriod(rawValue: raw) {
            analyticsPeriod = period
        }
        if let window = RecentlyAddedWindow(rawValue: defaults.integer(forKey: Self.windowKey)) {
            recentlyAddedWindow = window
        }
    }

    // MARK: - Data Fetching

    var lastLoadedAt: Date?

    func load() async {
        // Stamped up front so activations during a load don't start another.
        lastLoadedAt = .now
        async let catalog: Void = fetchCasks()
        async let local: Void = localHomebrew.refresh()
        async let categories: Void = categoryService.refreshFromRemote()
        async let addedDates: Void = recentlyAdded.refreshFromRemote()
        _ = await (catalog, local, categories, addedDates)
    }

    func refreshIfStale(maxAge: TimeInterval = 3600) async {
        guard let lastLoadedAt,
              Date.now.timeIntervalSince(lastLoadedAt) >= maxAge
        else { return }
        await load()
    }

    func fetchCasks() async {
        // A background refresh keeps showing the catalog it already has.
        isLoading = casks.isEmpty
        errorMessage = nil
        let span = CrashReporter.span(name: "catalog.fetch", operation: "http")

        do {
            async let caskRequest = apiClient.fetchAllCasks()
            async let analyticsRequest = apiClient.fetchAnalytics(period: .days365)

            let allCasks = try await caskRequest
            casks = allCasks.filter { cask in
                !cask.deprecated
                    && !cask.disabled
                    && !cask.token.contains("@")
                    && !cask.token.hasPrefix("font-")
            }
            await localHomebrew.updatePackageCatalog(casks)

            if let analytics = try? await analyticsRequest {
                analyticsByPeriod[.days365] = Self.countsByToken(from: analytics)
            }
            span.finish()
        } catch {
            if casks.isEmpty { errorMessage = error.localizedDescription }
            span.finish(error: error)
            CrashReporter.capture(error)
        }

        isLoading = false
    }

    func selectRecentlyAddedWindow(_ window: RecentlyAddedWindow) {
        recentlyAddedWindow = window
        defaults.set(window.rawValue, forKey: Self.windowKey)
    }

    func selectAnalyticsPeriod(_ period: AnalyticsPeriod) async {
        if analyticsByPeriod[period] != nil {
            commitAnalyticsPeriod(period)
            return
        }

        let requestID = UUID()
        analyticsRequestID = requestID
        do {
            let analytics = try await apiClient.fetchAnalytics(period: period)
            analyticsByPeriod[period] = Self.countsByToken(from: analytics)
            guard analyticsRequestID == requestID else { return }
            commitAnalyticsPeriod(period)
        } catch {
            guard analyticsRequestID == requestID else { return }
            let fallback = analyticsByPeriod[analyticsPeriod] != nil ? analyticsPeriod : .days365
            commitAnalyticsPeriod(fallback)
        }
    }

    private func commitAnalyticsPeriod(_ period: AnalyticsPeriod) {
        analyticsPeriod = period
        defaults.set(period.rawValue, forKey: Self.periodKey)
    }

    private static func countsByToken(from analytics: CaskAnalyticsResponse) -> [String: Int] {
        Dictionary(
            analytics.items.map { ($0.cask, $0.downloadCount) },
            uniquingKeysWith: max
        )
    }

    private func scheduleSearchApply() {
        searchDebounceTask?.cancel()
        // Clearing applies instantly; only typing debounces.
        guard !searchText.isEmpty, searchDebounceInterval > .zero else {
            appliedSearchText = searchText
            return
        }
        searchDebounceTask = Task { [interval = searchDebounceInterval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            appliedSearchText = searchText
        }
    }

    func formattedDownloads(for token: String) -> String? {
        guard let count = downloadCounts[token], count > 0 else { return nil }
        // ponytail: en_US pin keeps the K/M suffixes stable across locales
        return count.formatted(.number.notation(.compactName).locale(Locale(identifier: "en_US")))
    }
}
