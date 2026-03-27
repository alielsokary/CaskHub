//
//  CaskCatalogViewModel.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation
import Observation

enum SortOption: String, CaseIterable, Identifiable {
    case mostPopular = "Most Popular"
    case nameAZ = "Name (A→Z)"
    case nameZA = "Name (Z→A)"

    var id: String { rawValue }
}

@MainActor
@Observable
final class CaskCatalogViewModel {
    private(set) var casks: [Cask] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var downloadCounts: [String: Int] = [:]
    var searchText = ""
    var sortOption: SortOption = .mostPopular
    var selectedSidebar: SidebarSelection = .discover(.browse)

    private let apiClient: BrewAPIClientProtocol
    private let categoryService: CategoryService

    init(apiClient: BrewAPIClientProtocol = BrewAPIClient(), categoryService: CategoryService) {
        self.apiClient = apiClient
        self.categoryService = categoryService
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
            return casks
                .sorted { (downloadCounts[$0.token] ?? 0) > (downloadCounts[$1.token] ?? 0) }
                .prefix(100)
                .map { $0 }

        case .discover(.topCharts):
            return casks

        case .library(.installed):
            return casks.filter { $0.installed != nil }

        case .library(.updates):
            return casks.filter { $0.outdated }

        case .category(let categoryID):
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

    private func applySort(to casks: [Cask]) -> [Cask] {
        switch sortOption {
        case .mostPopular:
            return casks.sorted { (downloadCounts[$0.token] ?? 0) > (downloadCounts[$1.token] ?? 0) }
        case .nameAZ:
            return casks.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .nameZA:
            return casks.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending }
        }
    }

    // MARK: - Data Fetching

    func fetchCasks() async {
        isLoading = true
        errorMessage = nil

        do {
            async let caskRequest = apiClient.fetchAllCasks()
            async let analyticsRequest = apiClient.fetchAnalytics()

            let allCasks = try await caskRequest
            casks = allCasks.filter { cask in
                !cask.deprecated
                && !cask.disabled
                && !cask.token.contains("@")
                && !cask.token.hasPrefix("font-")
            }

            if let analytics = try? await analyticsRequest {
                downloadCounts = Dictionary(
                    uniqueKeysWithValues: analytics.items.map { ($0.cask, $0.downloadCount) }
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func formattedDownloads(for token: String) -> String? {
        guard let count = downloadCounts[token], count > 0 else { return nil }
        switch count {
        case 1_000_000...:
            return String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(count) / 1_000)
        default:
            return "\(count)"
        }
    }
}
