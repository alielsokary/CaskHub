//
//  CaskCatalogViewModel+Taps.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Foundation

struct TapSection: Identifiable {
    let tap: TapSummary
    let casks: [Cask]
    let formulae: [TapFormula]

    var id: String {
        tap.name
    }
}

extension CaskCatalogViewModel {
    static let tapSectionSize = 8

    var tapSections: [TapSection] {
        localHomebrew.tapIndex.taps.map { tap in
            let casks = Array(tapCasks(in: tap.name).prefix(Self.tapSectionSize))
            let formulae = tapFormulae(in: tap.name).prefix(Self.tapSectionSize - casks.count)
            return TapSection(tap: tap, casks: casks, formulae: Array(formulae))
        }
    }

    func tapHasMore(_ tapName: String) -> Bool {
        tapCasks(in: tapName).count + tapFormulae(in: tapName).count > Self.tapSectionSize
    }

    /// Search-filtered formulae of one tap, by name.
    func tapFormulae(in tapName: String) -> [TapFormula] {
        let query = appliedSearchText.lowercased()
        return localHomebrew.tapIndex.formulae
            .filter { $0.tap == tapName && (query.isEmpty || $0.searchKey.contains(query)) }
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
