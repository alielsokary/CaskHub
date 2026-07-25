//
//  CatalogProjectionCache.swift
//  CaskHub
//

import Foundation

struct CatalogLibrarySnapshot {
    let updatableCasks: [Cask]
    let installedCasks: [Cask]
    let adoptableCasks: [Cask]
    let categoryCounts: [String: Int]
    let localStates: [String: CaskLocalState]
}

final class MemoizedValue<Key: Equatable, Value> {
    private var entry: (key: Key, value: Value)?

    func value(for key: Key, create: () -> Value) -> Value {
        if let entry, entry.key == key {
            return entry.value
        }
        let value = create()
        entry = (key, value)
        return value
    }
}

struct CatalogLibraryCacheKey: Equatable {
    let catalogRevision: Int
    let installationRevision: Int
    let categoryRevision: Int
}

struct FilteredCatalogCacheKey: Equatable {
    let library: CatalogLibraryCacheKey
    let recentlyAddedRevision: Int
    let analyticsPeriod: AnalyticsPeriod
    let recentlyAddedWindow: RecentlyAddedWindow
    let selectedSidebar: SidebarSelection
    let searchText: String
    let sortOption: SortOption
}

struct BrowseCatalogCacheKey: Equatable {
    let catalogRevision: Int
    let categoryRevision: Int
    let recentlyAddedRevision: Int
    let recentlyAddedWindow: RecentlyAddedWindow
}
