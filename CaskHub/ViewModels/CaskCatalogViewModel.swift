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
    case newest = "Newest"
    case oldest = "Oldest"

    var id: String {
        rawValue
    }

    static let standard: [SortOption] = [.mostPopular, .nameAZ, .nameZA]
}

@MainActor
@Observable
final class CaskCatalogViewModel {
    private(set) var casks: [Cask] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var analyticsByPeriod: [AnalyticsPeriod: [String: Int]] = [:]
    private(set) var analyticsPeriod: AnalyticsPeriod = .days365
    private var analyticsRequestID = UUID()
    var searchText = ""

    private static let periodKey = "analyticsPeriod"
    private static let windowKey = "recentlyAddedWindow"

    var downloadCounts: [String: Int] {
        guard selectedSidebar == .discover(.topCharts) else {
            return analyticsByPeriod[.days365] ?? [:]
        }
        // Never label annual data as a shorter period while that period loads or fails.
        return analyticsByPeriod[analyticsPeriod] ?? [:]
    }

    var sortOption: SortOption = .mostPopular
    var selectedSidebar: SidebarSelection = .discover(.browse)

    private(set) var recentlyAddedWindow: RecentlyAddedWindow = .days30

    private let apiClient: BrewAPIClientProtocol
    private let categoryService: CategoryService
    private let recentlyAdded: RecentlyAddedService
    private let localHomebrew: LocalHomebrewService
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

    // MARK: - Sidebar Counts

    var updatableCasks: [Cask] {
        casks.filter { [localHomebrew] in
            localHomebrew.hasAvailableUpdate(token: $0.token, remoteVersion: $0.version, autoUpdates: $0.autoUpdates)
        }
    }

    var updatesCount: Int {
        updatableCasks.count
    }

    var installedCasks: [Cask] {
        casks.filter { [localHomebrew] in localHomebrew.isPresent($0) }
    }

    var installedCount: Int {
        installedCasks.count
    }

    var adoptableCasks: [Cask] {
        casks.filter { [localHomebrew] in localHomebrew.isAdoptable($0) }
    }

    var categoryCounts: [String: Int] {
        let catalogTokens = Set(casks.map(\.token))
        return categoryService.categoryTokenSets.mapValues {
            $0.intersection(catalogTokens).count
        }
    }

    // MARK: - Browse Sections

    private static let browseSectionSize = 8

    var browseSections: [BrowseSection] {
        let counts = analyticsByPeriod[.days365] ?? [:]
        func top(_ source: [Cask]) -> [Cask] {
            Array(sortedByDownloads(source, using: counts).prefix(Self.browseSectionSize))
        }

        let recentTokens = recentlyAdded.recentTokens(within: recentlyAddedWindow.rawValue)
        var sections = [
            BrowseSection(
                title: "Most Popular",
                destination: .discover(.topCharts),
                casks: top(casks)
            ),
            BrowseSection(
                title: "Recently Added",
                destination: .discover(.recentlyAdded),
                casks: Array(sortedByNewest(casks.filter { recentTokens.contains($0.token) }).prefix(Self.browseSectionSize))
            )
        ]
        for entry in categoryService.orderedCategories where entry.id != "other" {
            let tokens = categoryService.tokens(in: entry.id)
            sections.append(BrowseSection(
                title: entry.definition.displayName,
                destination: .category(entry.id),
                casks: top(casks.filter { tokens.contains($0.token) })
            ))
        }
        return sections.filter { !$0.casks.isEmpty }
    }

    // MARK: - Filtered Casks (3-stage pipeline)

    var filteredCasks: [Cask] {
        let sidebarFiltered = applySidebarFilter(to: casks)
        let searched = applySearch(to: sidebarFiltered)
        return applySort(to: searched)
    }

    private func applySidebarFilter(to casks: [Cask]) -> [Cask] {
        switch selectedSidebar {
        case .discover(.browse):
            return casks

        case .discover(.featured):
            return Array(sortedByDownloads(casks, using: downloadCounts).prefix(100))

        case .discover(.topCharts):
            return casks

        case .discover(.recentlyAdded):
            let recentTokens = recentlyAdded.recentTokens(within: recentlyAddedWindow.rawValue)
            return casks.filter { recentTokens.contains($0.token) }

        case .library(.installed):
            return installedCasks

        case .library(.updates):
            return updatableCasks

        case .library(.adopt):
            return adoptableCasks

        case let .category(categoryID):
            let tokens = categoryService.tokens(in: categoryID)
            return casks.filter { tokens.contains($0.token) }
        }
    }

    private func applySearch(to casks: [Cask]) -> [Cask] {
        guard !searchText.isEmpty else { return casks }
        let query = searchText.lowercased()
        return casks.filter { cask in
            cask.displayName.lowercased().contains(query)
                || cask.token.lowercased().contains(query)
                || (cask.desc?.lowercased().contains(query) ?? false)
        }
    }

    private func sortedByDownloads(_ source: [Cask], using counts: [String: Int]) -> [Cask] {
        source.sorted { (counts[$0.token] ?? 0) > (counts[$1.token] ?? 0) }
    }

    private func sortedByNewest(_ source: [Cask]) -> [Cask] {
        source.sorted { (recentlyAdded.addedDate(for: $0.token) ?? "") > (recentlyAdded.addedDate(for: $1.token) ?? "") }
    }

    private func applySort(to casks: [Cask]) -> [Cask] {
        switch sortOption {
        case .mostPopular:
            return sortedByDownloads(casks, using: downloadCounts)
        case .nameAZ:
            return casks.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .nameZA:
            return casks.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending }
        case .newest:
            return sortedByNewest(casks)
        case .oldest:
            return casks.sorted { (recentlyAdded.addedDate(for: $0.token) ?? "9999") < (recentlyAdded.addedDate(for: $1.token) ?? "9999") }
        }
    }

    // MARK: - Data Fetching

    func fetchCasks() async {
        isLoading = true
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
            errorMessage = error.localizedDescription
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

    func formattedDownloads(for token: String) -> String? {
        guard let count = downloadCounts[token], count > 0 else { return nil }
        // ponytail: en_US pin keeps the K/M suffixes stable across locales
        return count.formatted(.number.notation(.compactName).locale(Locale(identifier: "en_US")))
    }
}
