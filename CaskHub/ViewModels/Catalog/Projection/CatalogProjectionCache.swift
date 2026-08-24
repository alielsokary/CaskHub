//
//  CatalogProjectionCache.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

struct CatalogLibrarySnapshot {
    let updatableCasks: [Cask]
    let installedCasks: [Cask]
    let adoptableCasks: [Cask]
    let casksByCategory: [String: [Cask]]
    let categoryCounts: [String: Int]
    let localStates: [String: CaskLocalState]
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

struct CategoryPresentationCacheKey: Equatable {
    let catalogRevision: Int
    let categoryRevision: Int
}

struct BrowseCatalogCacheKey: Equatable {
    let catalogRevision: Int
    let categoryRevision: Int
    let recentlyAddedRevision: Int
    let recentlyAddedWindow: RecentlyAddedWindow
}
