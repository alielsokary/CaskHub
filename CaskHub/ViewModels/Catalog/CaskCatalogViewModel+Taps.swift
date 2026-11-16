//
//  CaskCatalogViewModel+Taps.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Foundation

struct TapSection: Identifiable {
    let tap: TapSummary
    /// The first `tapSectionSize` matches.
    let casks: [Cask]
    let matchCount: Int

    var id: String {
        tap.name
    }
}

extension CaskCatalogViewModel {
    static let tapSectionSize = 8

    var tapSections: [TapSection] {
        localHomebrew.tapIndex.tapsWithCasks.map { tap in
            let matches = tapCasks(in: tap.name)
            return TapSection(tap: tap, casks: Array(matches.prefix(Self.tapSectionSize)), matchCount: matches.count)
        }
    }

    /// Search-filtered casks of one tap, by display name.
    func tapCasks(in tapName: String) -> [Cask] {
        let query = appliedSearchText.lowercased()
        return catalog.tapCasks
            .filter { $0.tap == tapName && (query.isEmpty || $0.searchKey.contains(query)) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func addTap(_ request: TapAddRequest) async throws {
        defer { applyTapIndex() }
        try await localHomebrew.addTap(request)
    }

    func removalPreview(for tapName: String) async -> TapRemovalPreview {
        await localHomebrew.removalPreview(for: tapName)
    }

    func removeTap(_ preview: TapRemovalPreview) async throws {
        defer { applyTapIndex() }
        try await localHomebrew.removeTap(preview)
    }
}
