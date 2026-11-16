//
//  CatalogProjectionCache.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated struct CatalogLibrarySnapshot: Sendable {
    let updatableCasks: [Cask]
    let installedCasks: [Cask]
    let homebrewInstalledCasks: [Cask]
    let adoptableCasks: [Cask]
    let casksByCategory: [String: [Cask]]
    let categoryCounts: [String: Int]
    let retiredCasksByCategory: [String: [Cask]]
    let localStates: [String: CaskLocalState]

    static let empty = CatalogLibrarySnapshot(
        updatableCasks: [], installedCasks: [], homebrewInstalledCasks: [], adoptableCasks: [],
        casksByCategory: [:], categoryCounts: [:], retiredCasksByCategory: [:], localStates: [:]
    )
}

final class BoundedMemoizedValues<Key: Equatable, Value> {
    private let capacity: Int
    private var entries: [(key: Key, value: Value)] = []

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        entries.reserveCapacity(capacity)
    }

    func value(for key: Key, create: () -> Value) -> Value {
        if let index = entries.firstIndex(where: { $0.key == key }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.value
        }

        let value = create()
        if entries.count == capacity {
            entries.removeFirst()
        }
        entries.append((key, value))
        return value
    }
}

nonisolated struct CatalogLibraryCacheKey: Equatable, Sendable {
    let catalogRevision: Int
    let installationRevision: Int
    let categoryRevision: Int
}

struct FilteredCatalogCacheKey: Equatable {
    let library: CatalogLibraryCacheKey
    /// Filtering reads the published snapshot, so its key must change when that snapshot does.
    let derived: CatalogDerivedKey?
    let analyticsRevision: Int
    let recentlyAddedRevision: Int
    let analyticsPeriod: AnalyticsPeriod
    let recentlyAddedWindow: RecentlyAddedWindow
    let selectedSidebar: SidebarSelection
    let searchText: String
    let sortOption: SortOption
}

nonisolated struct CategoryPresentationCacheKey: Equatable, Sendable {
    let catalogRevision: Int
    let categoryRevision: Int
}

nonisolated struct BrowseCatalogCacheKey: Equatable, Sendable {
    let catalogRevision: Int
    let categoryRevision: Int
    let recentlyAddedRevision: Int
    let recentlyAddedWindow: RecentlyAddedWindow
    let analyticsRevision: Int
}

nonisolated struct CatalogDerivedKey: Equatable, Sendable {
    let library: CatalogLibraryCacheKey
    let browse: BrowseCatalogCacheKey

    var presentation: CategoryPresentationCacheKey {
        CategoryPresentationCacheKey(catalogRevision: library.catalogRevision, categoryRevision: library.categoryRevision)
    }
}

/// Catalog-wide projections, built off the main actor and published as one value.
nonisolated struct CatalogDerivedData: Sendable {
    let key: CatalogDerivedKey?
    let library: CatalogLibrarySnapshot
    let browseSections: [BrowseSection]
    let categoryPresentations: [String: CaskCategoryPresentation]
    let searchKeys: [String: String]
    let nameRanks: [String: Int]

    static let empty = CatalogDerivedData(
        key: nil, library: .empty, browseSections: [], categoryPresentations: [:], searchKeys: [:], nameRanks: [:]
    )
}

/// Captured on the main actor; a nil part means the previous snapshot's part still matches its key.
nonisolated struct CatalogDerivedInput: Sendable {
    let key: CatalogDerivedKey
    let catalog: CatalogPartition
    let library: CatalogLibraryInput?
    let presentation: CatalogPresentationInput?
    let browse: CatalogBrowseProjectionInput?
}

nonisolated struct CatalogLibraryInput: Sendable {
    let installedCasks: [String: LocalCaskInstallation]
    let resolver: CaskLocalStateResolver
    let categoryMappings: [String: TokenCategoryMapping]
    let officialTwins: Set<String>
    let adoptIgnoredTokens: Set<String>
}

nonisolated struct CatalogPresentationInput: Sendable {
    let categoryMappings: [String: TokenCategoryMapping]
    let definitions: [CategoryID: CategoryDefinition]
}

nonisolated extension CatalogDerivedData {
    @concurrent
    static func build(_ input: CatalogDerivedInput, reusing previous: CatalogDerivedData) async -> CatalogDerivedData {
        let catalog = input.catalog
        let catalogChanged = previous.key?.library.catalogRevision != input.key.library.catalogRevision
        let everyCask = catalog.browsable + catalog.retired + catalog.tapCasks
        return CatalogDerivedData(
            key: input.key,
            library: input.library.map { makeLibrary($0, catalog: catalog) } ?? previous.library,
            browseSections: input.browse.map {
                CatalogProjector.makeBrowseSections(from: $0, sectionSize: CaskCatalogViewModel.browseSectionSize)
            } ?? previous.browseSections,
            categoryPresentations: input.presentation.map {
                makePresentations($0, casks: catalog.browsable + catalog.retired)
            } ?? previous.categoryPresentations,
            searchKeys: catalogChanged
                ? Dictionary(everyCask.map { ($0.reference, $0.searchKey) }) { first, _ in first }
                : previous.searchKeys,
            nameRanks: catalogChanged ? makeNameRanks(everyCask) : previous.nameRanks
        )
    }

    private static func makeLibrary(_ input: CatalogLibraryInput, catalog: CatalogPartition) -> CatalogLibrarySnapshot {
        let installedOnly = CatalogProjector.installedOnlyCasks(installations: input.installedCasks, partition: catalog)
        let libraryCasks = catalog.browsable + catalog.tapCasks
        let localStates = (libraryCasks + installedOnly + catalog.retired).reduce(into: [String: CaskLocalState]()) {
            $0[$1.reference] = input.resolver.localState(for: $1)
        }
        return CatalogProjector.makeLibrary(from: CatalogLibraryProjectionInput(
            casks: libraryCasks,
            installedOnlyCasks: installedOnly,
            retiredCasks: catalog.retired,
            localStates: localStates,
            categoryMappings: input.categoryMappings,
            officialTwins: input.officialTwins,
            adoptIgnoredTokens: input.adoptIgnoredTokens
        ))
    }

    private static func makePresentations(
        _ input: CatalogPresentationInput, casks: [Cask]
    ) -> [String: CaskCategoryPresentation] {
        var result = [String: CaskCategoryPresentation](minimumCapacity: casks.count)
        for cask in casks {
            result[cask.token] = CaskCategoryProjector.make(
                token: cask.token, mappings: input.categoryMappings, definitions: input.definitions
            )
        }
        return result
    }

    /// Collation-equal names share a rank so descending sorts keep ties stable.
    private static func makeNameRanks(_ casks: [Cask]) -> [String: Int] {
        let sorted = casks.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        var ranks: [String: Int] = [:]
        ranks.reserveCapacity(sorted.count)
        var rank = 0
        for (index, cask) in sorted.enumerated() {
            if index > 0,
               sorted[index - 1].displayName.localizedCaseInsensitiveCompare(cask.displayName) != .orderedSame {
                rank = index
            }
            if ranks[cask.reference] == nil { ranks[cask.reference] = rank }
        }
        return ranks
    }
}
