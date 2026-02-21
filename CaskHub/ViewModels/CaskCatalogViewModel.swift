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

    var filteredCasks: [Cask] {
        let searched: [Cask]
        if searchText.isEmpty {
            searched = casks
        } else {
            let query = searchText.lowercased()
            searched = casks.filter { cask in
                cask.displayName.lowercased().contains(query)
                || cask.token.lowercased().contains(query)
                || (cask.desc?.lowercased().contains(query) ?? false)
            }
        }

        switch sortOption {
        case .mostPopular:
            return searched.sorted { (downloadCounts[$0.token] ?? 0) > (downloadCounts[$1.token] ?? 0) }
        case .nameAZ:
            return searched.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .nameZA:
            return searched.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending }
        }
    }

    private let apiClient: BrewAPIClientProtocol

    init(apiClient: BrewAPIClientProtocol = BrewAPIClient()) {
        self.apiClient = apiClient
    }

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
