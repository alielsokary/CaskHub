//
//  CaskCatalogViewModel.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation
import Observation

/// One shelf on the Browse page: a titled row group with a "View All" destination.
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

    /// Date sorts only make sense where add dates drive the page.
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
    var searchText = ""

    /// Top Charts respects the picked period; every other section stays on 365d.
    /// Falls back to 365d while a shorter period is still loading so the
    /// popularity sort doesn't collapse to arbitrary order.
    var downloadCounts: [String: Int] {
        guard selectedSidebar == .discover(.topCharts) else {
            return analyticsByPeriod[.days365] ?? [:]
        }
        return analyticsByPeriod[analyticsPeriod]
            ?? analyticsByPeriod[.days365]
            ?? [:]
    }

    var sortOption: SortOption = .mostPopular
    var selectedSidebar: SidebarSelection = .discover(.browse)

    /// Window for the Recently Added page and Browse shelf.
    var recentlyAddedWindow: RecentlyAddedWindow = .days30

    private let apiClient: BrewAPIClientProtocol
    private let categoryService: CategoryService
    private let recentlyAdded: RecentlyAddedService
    private let localHomebrew: LocalHomebrewService

    init(
        apiClient: BrewAPIClientProtocol,
        categoryService: CategoryService,
        recentlyAdded: RecentlyAddedService,
        localHomebrew: LocalHomebrewService
    ) {
        self.apiClient = apiClient
        self.categoryService = categoryService
        self.recentlyAdded = recentlyAdded
        self.localHomebrew = localHomebrew
    }

    // MARK: - Sidebar Counts

    /// Number of locally-installed, non-auto-updating casks whose installed
    /// version differs from the latest available version in the catalog.
    var updatesCount: Int {
        casks.lazy
            .filter { [localHomebrew] in
                localHomebrew.hasAvailableUpdate(token: $0.token, remoteVersion: $0.version, autoUpdates: $0.autoUpdates)
            }
            .count
    }

    /// Category ID → number of catalog casks in it (intersected with the
    /// mapping data, so sidebar counts match what clicking the category shows).
    var categoryCounts: [String: Int] {
        let catalogTokens = Set(casks.map(\.token))
        return categoryService.categoryTokenSets.mapValues {
            $0.intersection(catalogTokens).count
        }
    }

    // MARK: - Browse Sections

    /// Cards per Browse shelf: two rows of the fixed 4-column grid.
    private static let browseSectionSize = 8

    /// Shelves for the Browse page: Most Popular, Recently Added (newest
    /// first), then every category except "other" — the rest holding their
    /// top casks by 365d downloads.
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
            return casks.filter { localHomebrew.isInstalled(token: $0.token) }

        case .library(.updates):
            return casks.filter {
                localHomebrew.hasAvailableUpdate(token: $0.token, remoteVersion: $0.version, autoUpdates: $0.autoUpdates)
            }

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

    /// Switches the Top Charts window, fetching that period's data on first use.
    func selectAnalyticsPeriod(_ period: AnalyticsPeriod) async {
        analyticsPeriod = period
        guard analyticsByPeriod[period] == nil else { return }
        if let analytics = try? await apiClient.fetchAnalytics(period: period) {
            analyticsByPeriod[period] = Self.countsByToken(from: analytics)
        }
    }

    private static func countsByToken(from analytics: CaskAnalyticsResponse) -> [String: Int] {
        Dictionary(
            analytics.items.map { ($0.cask, $0.downloadCount) },
            uniquingKeysWith: max
        )
    }

    func formattedDownloads(for token: String) -> String? {
        guard let count = downloadCounts[token], count > 0 else { return nil }
        switch count {
        case 1_000_000...:
            return String(format: "%.1fM", Double(count) / 1_000_000)
        case 1000...:
            return String(format: "%.1fK", Double(count) / 1000)
        default:
            return "\(count)"
        }
    }
}
