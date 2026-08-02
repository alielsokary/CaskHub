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

    func categoryPresentation(for cask: Cask) -> CaskCategoryPresentation? {
        CaskCategoryProjector.make(
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

    /// One lowercase pass per catalog load instead of three per cask per search.
    private var searchKeys: [String: String] {
        searchKeysCache.value(for: catalogRevision) { [casks] in
            Dictionary(casks.map { ($0.token, $0.searchKey) }) { first, _ in first }
        }
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
                searchKeys: appliedSearchText.isEmpty ? [:] : searchKeys
            ))
        }
    }
}
