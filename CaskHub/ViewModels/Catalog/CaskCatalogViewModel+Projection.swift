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

    func installedCount(includingExternallyManaged: Bool) -> Int {
        includingExternallyManaged ? installedCount : librarySnapshot.homebrewInstalledCasks.count
    }

    var adoptableCasks: [Cask] {
        librarySnapshot.adoptableCasks
    }

    /// Newest ignore first, matching the design's "just now" on top.
    var adoptIgnoredCasks: [Cask] {
        let dates = localHomebrew.adoptIgnoredDates
        guard !dates.isEmpty else { return [] }
        return casks
            .filter { dates[$0.token] != nil }
            .sorted { lhs, rhs in
                let lhsDate = dates[lhs.token] ?? .distantPast
                let rhsDate = dates[rhs.token] ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.token < rhs.token
            }
    }

    var pinnedCasks: [Cask] {
        Self.sortedByName(librarySnapshot.homebrewInstalledCasks.filter {
            localHomebrew.pinnedVersion(for: $0.reference) != nil
        })
    }

    func pinnableCasks(matching query: String) -> [Cask] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return Self.sortedByName(librarySnapshot.homebrewInstalledCasks.filter { cask in
            localHomebrew.pinnedVersion(for: cask.reference) == nil
                && !localState(for: cask).isZombie
                && (query.isEmpty
                    || cask.displayName.localizedStandardContains(query)
                    || cask.token.localizedStandardContains(query))
        })
    }

    private static func sortedByName(_ casks: [Cask]) -> [Cask] {
        casks.sorted { lhs, rhs in
            switch lhs.displayName.localizedStandardCompare(rhs.displayName) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.reference < rhs.reference
            }
        }
    }

    var categoryCounts: [String: Int] {
        librarySnapshot.categoryCounts
    }

    /// Live per cask while the library snapshot rebuilds, so a finished install never flashes its old state.
    func localState(for cask: Cask) -> CaskLocalState {
        let derived = currentDerived
        guard derived.key?.library == libraryCacheKey,
              let state = derived.library.localStates[cask.reference]
        else { return localHomebrew.localState(for: cask) }
        return state
    }

    /// CaskFlow's mappings, tap casks it covers (by reference), and the built-in Fonts category for every `font-` cask.
    var categoryMappings: [String: TokenCategoryMapping] {
        let key = CategoryPresentationCacheKey(
            catalogRevision: catalogRevision,
            categoryRevision: categoryService.catalogStateRevision
        )
        return categoryMappingsCache.value(for: key) { [catalog, categoryService] in
            var mappings = categoryService.tokenMappings
            for cask in catalog.all where cask.isFont && mappings[cask.token] == nil {
                mappings[cask.token] = TokenCategoryMapping(primary: CategoryService.fontsCategoryID, secondary: [])
            }
            for cask in catalog.tapCasks {
                mappings[cask.reference] = categoryService.mapping(for: cask.reference)
            }
            return mappings
        }
    }

    private var categoryPresentations: [String: CaskCategoryPresentation] {
        currentDerived.categoryPresentations
    }

    func categoryPresentation(for cask: Cask) -> CaskCategoryPresentation? {
        guard CaskReference.isOfficial(tap: cask.tap) else {
            return CaskCategoryProjector.make(
                token: cask.reference, mappings: categoryMappings, definitions: categoryService.categoryDefinitions
            )
        }
        return categoryPresentations[cask.token] ?? CaskCategoryProjector.make(
            token: cask.token,
            mappings: categoryMappings,
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
        currentDerived.library
    }

    // MARK: - Derived Data

    private var derivedKey: CatalogDerivedKey {
        CatalogDerivedKey(
            library: libraryCacheKey,
            browse: BrowseCatalogCacheKey(
                catalogRevision: catalogRevision,
                categoryRevision: categoryService.catalogStateRevision,
                recentlyAddedRevision: recentlyAdded.catalogStateRevision,
                recentlyAddedWindow: recentlyAddedWindow,
                analyticsRevision: analyticsRevision
            )
        )
    }

    /// The last published snapshot, possibly stale; a stale one schedules its rebuild.
    private var currentDerived: CatalogDerivedData {
        let key = derivedKey
        if derived.key != key { scheduleDerivedRebuild(for: key) }
        return derived
    }

    /// Resolves once every catalog-wide projection matches the current inputs.
    func projectionsSettled() async {
        while true {
            let key = derivedKey
            if derived.key == key { return }
            scheduleDerivedRebuild(for: key)
            await derivedTask?.value
        }
    }

    private func scheduleDerivedRebuild(for key: CatalogDerivedKey) {
        guard requestedDerivedKey != key else { return }
        requestedDerivedKey = key
        let previous = derived
        let input = derivedInput(for: key, previous: previous.key)
        derivedTask = Task {
            let built = await CatalogDerivedData.build(input, reusing: previous)
            guard requestedDerivedKey == key else { return }
            derived = built
        }
    }

    private func derivedInput(for key: CatalogDerivedKey, previous: CatalogDerivedKey?) -> CatalogDerivedInput {
        CatalogDerivedInput(
            key: key,
            catalog: catalog,
            library: previous?.library == key.library ? nil : CatalogLibraryInput(
                installedCasks: localHomebrew.installationSnapshot.installedCasks,
                resolver: localHomebrew.localStateResolver(),
                categoryMappings: categoryMappings,
                officialTwins: Set(catalog.tapCasks.map(\.reference).filter { categoryService.officialAlias(for: $0) != nil }),
                adoptIgnoredTokens: Set(localHomebrew.adoptIgnoredDates.keys)
            ),
            presentation: previous?.presentation == key.presentation ? nil : CatalogPresentationInput(
                categoryMappings: categoryMappings,
                definitions: categoryService.categoryDefinitions
            ),
            browse: previous?.browse == key.browse ? nil : CatalogBrowseProjectionInput(
                casks: casks,
                annualDownloadCounts: analyticsByPeriod[.days365] ?? [:],
                categoryMappings: categoryMappings,
                orderedCategories: categoryService.orderedCategories.map {
                    (id: $0.id, displayName: categoryService.displayName(for: $0.id))
                },
                recentTokens: recentlyAdded.recentTokens(within: recentlyAddedWindow.rawValue),
                addedDates: recentlyAdded.addedDates
            )
        )
    }

    // MARK: - Browse Sections

    nonisolated static let browseSectionSize = 8

    var browseSections: [BrowseSection] {
        currentDerived.browseSections
    }

    /// The CaskFlow house pick, else the Most Popular shelf head; never the current sort.
    var heroCask: Cask? {
        if let token = categoryService.housePick?.token,
           let pick = catalogCask(for: token), pick.isBrowsable, !pick.isFont {
            return pick
        }
        // Without counts the shelf is in catalog (alphabetical) order.
        guard analyticsByPeriod[.days365]?.isEmpty == false else { return nil }
        return browseSections.first { $0.destination == .discover(.topCharts) }?.casks.first
    }

    // MARK: - Filtered Casks

    private var searchKeys: [String: String] {
        currentDerived.searchKeys
    }

    private var nameRanks: [String: Int] {
        currentDerived.nameRanks
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
        filteredCache.value(for: filteredCacheKey) {
            CatalogProjector.makeFiltered(from: filteredProjectionInput)
        }
    }

    var filteredExternallyManagedCasks: [Cask] {
        externallyManagedCache.value(for: filteredCacheKey) {
            CatalogProjector.makeExternallyManaged(from: filteredProjectionInput)
        }
    }

    private var filteredCacheKey: FilteredCatalogCacheKey {
        FilteredCatalogCacheKey(
            library: libraryCacheKey,
            derived: currentDerived.key,
            analyticsRevision: analyticsRevision,
            recentlyAddedRevision: recentlyAdded.catalogStateRevision,
            analyticsPeriod: analyticsPeriod,
            recentlyAddedWindow: recentlyAddedWindow,
            selectedSidebar: selectedSidebar,
            searchText: appliedSearchText,
            sortOption: sortOption
        )
    }

    private var filteredProjectionInput: CatalogFilteredProjectionInput {
        CatalogFilteredProjectionInput(
            casks: casks,
            tapCasks: catalog.tapCasks,
            retiredCasks: retiredCasks,
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
        )
    }
}
