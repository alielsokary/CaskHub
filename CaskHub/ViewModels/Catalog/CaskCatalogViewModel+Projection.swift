//
//  CaskCatalogViewModel+Projection.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

extension CaskCatalogViewModel {
    // MARK: - Sidebar Counts

    var updatableCasks: [Cask] {
        librarySnapshot.updatableCasks
    }

    var updatesCount: Int {
        updatableCasks.count
    }

    var installedCasks: [Cask] {
        librarySnapshot.installedCasks
    }

    var installedCount: Int {
        installedCasks.count
    }

    var adoptableCasks: [Cask] {
        librarySnapshot.adoptableCasks
    }

    var categoryCounts: [String: Int] {
        librarySnapshot.categoryCounts
    }

    func localState(for cask: Cask) -> CaskLocalState {
        librarySnapshot.localStates[cask.token] ?? localHomebrew.localState(for: cask)
    }

    private var categoryPresentations: [String: CaskCategoryPresentation] {
        let key = CategoryPresentationCacheKey(
            catalogRevision: catalogRevision,
            categoryRevision: categoryService.catalogStateRevision
        )
        return categoryPresentationCache.value(for: key) { [casks, categoryService] in
            var result = [String: CaskCategoryPresentation](minimumCapacity: casks.count)
            for cask in casks {
                result[cask.token] = CaskCategoryProjector.make(
                    token: cask.token,
                    mappings: categoryService.tokenMappings,
                    definitions: categoryService.categoryDefinitions
                )
            }
            return result
        }
    }

    func categoryPresentation(for cask: Cask) -> CaskCategoryPresentation? {
        categoryPresentations[cask.token] ?? CaskCategoryProjector.make(
            token: cask.token,
            mappings: categoryService.tokenMappings,
            definitions: categoryService.categoryDefinitions
        )
    }

    private var libraryCacheKey: CatalogLibraryCacheKey {
        CatalogLibraryCacheKey(
            catalogRevision: catalogRevision,
            installationRevision: localHomebrew.catalogStateRevision,
            categoryRevision: categoryService.catalogStateRevision
        )
    }

    private var librarySnapshot: CatalogLibrarySnapshot {
        libraryCache.value(for: libraryCacheKey) { [casks, categoryService, localHomebrew] in
            return CatalogProjector.makeLibrary(from: CatalogLibraryProjectionInput(
                casks: casks,
                localStates: localHomebrew.localStates(for: casks),
                categoryMappings: categoryService.tokenMappings
            ))
        }
    }

    // MARK: - Browse Sections

    private static let browseSectionSize = 8

    var browseSections: [BrowseSection] {
        let key = BrowseCatalogCacheKey(
            catalogRevision: catalogRevision,
            categoryRevision: categoryService.catalogStateRevision,
            recentlyAddedRevision: recentlyAdded.catalogStateRevision,
            recentlyAddedWindow: recentlyAddedWindow
        )
        return browseCache.value(for: key) {
            CatalogProjector.makeBrowseSections(
                from: CatalogBrowseProjectionInput(
                    casks: casks,
                    annualDownloadCounts: analyticsByPeriod[.days365] ?? [:],
                    categoryMappings: categoryService.tokenMappings,
                    orderedCategories: categoryService.orderedCategories.map {
                        (id: $0.id, displayName: $0.definition.displayName)
                    },
                    recentTokens: recentlyAdded.recentTokens(
                        within: recentlyAddedWindow.rawValue
                    ),
                    addedDates: recentlyAdded.addedDates
                ),
                sectionSize: Self.browseSectionSize
            )
        }
    }

    // MARK: - Filtered Casks

    private var searchKeys: [String: String] {
        searchKeysCache.value(for: catalogRevision) { [casks] in
            Dictionary(casks.map { ($0.token, $0.searchKey) }) { first, _ in first }
        }
    }

    /// Collation-equal names share a rank so descending sorts keep ties stable.
    private var nameRanks: [String: Int] {
        nameRankCache.value(for: catalogRevision) { [casks] in
            let sorted = casks.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                    == .orderedAscending
            }
            var ranks: [String: Int] = [:]
            ranks.reserveCapacity(sorted.count)
            var rank = 0
            for (index, cask) in sorted.enumerated() {
                if index > 0,
                   sorted[index - 1].displayName.localizedCaseInsensitiveCompare(
                       cask.displayName
                   ) != .orderedSame {
                    rank = index
                }
                if ranks[cask.token] == nil { ranks[cask.token] = rank }
            }
            return ranks
        }
    }

    private var sortUsesNameRanks: Bool {
        switch sortOption {
        case .nameAZ, .nameZA, .recentlyInstalled: return true
        case .mostPopular, .newest, .oldest: return false
        }
    }

    /// Render slice; `filteredCasks` stays uncapped for counts and the hero.
    var displayedCasks: [Cask] {
        let filtered = filteredCasks
        guard filtered.count > revealedCount else { return filtered }
        return Array(filtered.prefix(revealedCount))
    }

    var hasMoreToReveal: Bool {
        filteredCasks.count > revealedCount
    }

    var filteredCasks: [Cask] {
        let key = FilteredCatalogCacheKey(
            library: libraryCacheKey,
            recentlyAddedRevision: recentlyAdded.catalogStateRevision,
            analyticsPeriod: analyticsPeriod,
            recentlyAddedWindow: recentlyAddedWindow,
            selectedSidebar: selectedSidebar,
            searchText: appliedSearchText,
            sortOption: sortOption
        )
        return filteredCache.value(for: key) {
            CatalogProjector.makeFiltered(from: CatalogFilteredProjectionInput(
                casks: casks,
                library: librarySnapshot,
                selectedSidebar: selectedSidebar,
                searchText: appliedSearchText,
                sortOption: sortOption,
                downloadCounts: downloadCounts,
                recentTokens: recentlyAdded.recentTokens(
                    within: recentlyAddedWindow.rawValue
                ),
                addedDates: recentlyAdded.addedDates,
                installedDates: localHomebrew.installationSnapshot.installedCasks
                    .compactMapValues(\.installedAt),
                searchKeys: appliedSearchText.isEmpty ? [:] : searchKeys,
                nameRanks: sortUsesNameRanks ? nameRanks : [:]
            ))
        }
    }
}
