//
//  CatalogProjector.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

struct CatalogLibraryProjectionInput {
    let casks: [Cask]
    let localStates: [String: CaskLocalState]
    let categoryMappings: [String: TokenCategoryMapping]
}

struct CatalogBrowseProjectionInput {
    let casks: [Cask]
    let annualDownloadCounts: [String: Int]
    let categoryMappings: [String: TokenCategoryMapping]
    let orderedCategories: [(id: String, displayName: String)]
    let recentTokens: Set<String>
    let addedDates: [String: String]
}

struct CatalogFilteredProjectionInput {
    let casks: [Cask]
    let library: CatalogLibrarySnapshot
    let selectedSidebar: SidebarSelection
    let searchText: String
    let sortOption: SortOption
    let downloadCounts: [String: Int]
    let recentTokens: Set<String>
    let addedDates: [String: String]
    let installedDates: [String: Date]
    var searchKeys: [String: String] = [:]
}

enum CatalogProjector {
    static func makeLibrary(
        from input: CatalogLibraryProjectionInput
    ) -> CatalogLibrarySnapshot {
        var updatableCasks: [Cask] = []
        var installedCasks: [Cask] = []
        var adoptableCasks: [Cask] = []
        var casksByCategory: [String: [Cask]] = [:]

        for cask in input.casks {
            guard let localState = input.localStates[cask.token] else { continue }
            if localState.hasAvailableUpdate {
                updatableCasks.append(cask)
            }
            if localState.isPresent {
                installedCasks.append(cask)
            }
            if localState.isAdoptable {
                adoptableCasks.append(cask)
            }
            if let mapping = input.categoryMappings[cask.token] {
                for categoryID in Set([mapping.primary] + mapping.secondary) {
                    casksByCategory[categoryID, default: []].append(cask)
                }
            }
        }

        return CatalogLibrarySnapshot(
            updatableCasks: updatableCasks,
            installedCasks: installedCasks,
            adoptableCasks: adoptableCasks,
            casksByCategory: casksByCategory,
            categoryCounts: casksByCategory.mapValues(\.count),
            localStates: input.localStates
        )
    }

    static func makeBrowseSections(
        from input: CatalogBrowseProjectionInput,
        sectionSize: Int
    ) -> [BrowseSection] {
        let popularityOrder = sortedByDownloads(
            input.casks,
            using: input.annualDownloadCounts
        )
        var casksByCategory: [String: [Cask]] = [:]
        for cask in popularityOrder {
            guard let mapping = input.categoryMappings[cask.token] else { continue }
            for categoryID in Set([mapping.primary] + mapping.secondary)
                where casksByCategory[categoryID, default: []].count < sectionSize {
                casksByCategory[categoryID, default: []].append(cask)
            }
        }

        var sections = [
            BrowseSection(
                title: "Most Popular",
                destination: .discover(.topCharts),
                casks: Array(popularityOrder.prefix(sectionSize))
            ),
            BrowseSection(
                title: "Recently Added",
                destination: .discover(.recentlyAdded),
                casks: Array(sortedByNewest(
                    input.casks.filter {
                        isRecent($0.token, in: input.recentTokens, addedDates: input.addedDates)
                    },
                    addedDates: input.addedDates
                ).prefix(sectionSize))
            )
        ]
        for category in input.orderedCategories where category.id != "other" {
            sections.append(BrowseSection(
                title: category.displayName,
                destination: .category(category.id),
                casks: casksByCategory[category.id] ?? []
            ))
        }
        return sections.filter { !$0.casks.isEmpty }
    }

    static func makeFiltered(
        from input: CatalogFilteredProjectionInput
    ) -> [Cask] {
        let filtered = applySidebarFilter(input)
        let searched = applySearch(input.searchText, to: filtered, keys: input.searchKeys)
        return applySort(input.sortOption, to: searched, input: input)
    }

    private static func applySidebarFilter(
        _ input: CatalogFilteredProjectionInput
    ) -> [Cask] {
        switch input.selectedSidebar {
        case .discover(.browse):
            return input.casks
        case .discover(.featured):
            return Array(sortedByDownloads(
                input.casks,
                using: input.downloadCounts
            ).prefix(100))
        case .discover(.topCharts):
            return input.casks
        case .discover(.recentlyAdded):
            return input.casks.filter {
                isRecent($0.token, in: input.recentTokens, addedDates: input.addedDates)
            }
        case .library(.installed):
            return input.library.installedCasks
        case .library(.updates):
            return input.library.updatableCasks
        case .library(.adopt):
            return input.library.adoptableCasks
        case let .category(categoryID):
            return input.library.casksByCategory[categoryID] ?? []
        }
    }

    private static func applySearch(
        _ searchText: String,
        to casks: [Cask],
        keys: [String: String]
    ) -> [Cask] {
        guard !searchText.isEmpty else { return casks }
        let query = searchText.lowercased()
        return casks.filter { cask in
            (keys[cask.token] ?? cask.searchKey).contains(query)
        }
    }

    private static func applySort(
        _ sortOption: SortOption,
        to casks: [Cask],
        input: CatalogFilteredProjectionInput
    ) -> [Cask] {
        switch sortOption {
        case .mostPopular:
            return sortedByDownloads(casks, using: input.downloadCounts)
        case .nameAZ:
            return casks.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                    == .orderedAscending
            }
        case .nameZA:
            return casks.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                    == .orderedDescending
            }
        case .recentlyInstalled:
            return casks.sorted { lhs, rhs in
                let lhsDate = input.installedDates[lhs.token]
                let rhsDate = input.installedDates[rhs.token]
                if lhsDate != rhsDate {
                    if let lhsDate, let rhsDate { return lhsDate > rhsDate }
                    return lhsDate != nil
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                    == .orderedAscending
            }
        case .newest:
            return sortedByNewest(casks, addedDates: input.addedDates)
        case .oldest:
            return casks.sorted {
                (input.addedDates[$0.token] ?? "9999")
                    < (input.addedDates[$1.token] ?? "9999")
            }
        }
    }

    private static func sortedByDownloads(
        _ casks: [Cask],
        using counts: [String: Int]
    ) -> [Cask] {
        casks.sorted { (counts[$0.token] ?? 0) > (counts[$1.token] ?? 0) }
    }

    // Catalog tokens absent from the mined dates postdate the last mine, so they
    // are the newest casks; an empty dictionary means the data never loaded.
    private static func isRecent(
        _ token: String,
        in recentTokens: Set<String>,
        addedDates: [String: String]
    ) -> Bool {
        recentTokens.contains(token)
            || (!addedDates.isEmpty && addedDates[token] == nil)
    }

    private static func sortedByNewest(
        _ casks: [Cask],
        addedDates: [String: String]
    ) -> [Cask] {
        casks.sorted {
            (addedDates[$0.token] ?? "9999") > (addedDates[$1.token] ?? "9999")
        }
    }
}
