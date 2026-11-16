//
//  CatalogProjector.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

/// Every API cask, split once per fetch so Discover pages keep reading only browsable ones.
nonisolated struct CatalogPartition: Equatable {
    let all: [Cask]
    let browsable: [Cask]
    /// Deprecated or disabled main casks: found by search, never listed.
    let retired: [Cask]
    /// Third-party tap casks: searchable and manageable, never on Discover pages or in categories.
    let tapCasks: [Cask]
    let byReference: [String: Cask]

    init(_ all: [Cask], tapCasks: [Cask]) {
        self.all = all
        browsable = all.filter(\.isBrowsable)
        retired = all.filter { ($0.deprecated || $0.disabled) && !$0.token.contains("@") }
        self.tapCasks = tapCasks
        byReference = Dictionary((all + tapCasks).map { ($0.reference, $0) }) { first, _ in first }
    }
}

nonisolated struct CatalogLibraryProjectionInput {
    let casks: [Cask]
    /// Installed casks Discover pages never list: retired, font, `@` variants, and receipt-built rows.
    let installedOnlyCasks: [Cask]
    let retiredCasks: [Cask]
    let localStates: [String: CaskLocalState]
    let categoryMappings: [String: TokenCategoryMapping]
    /// Tap casks CaskFlow matched to an official cask; that cask already stands for them on category pages.
    let officialTwins: Set<String>
    let adoptIgnoredTokens: Set<String>
}

nonisolated struct CatalogBrowseProjectionInput {
    let casks: [Cask]
    let annualDownloadCounts: [String: Int]
    let categoryMappings: [String: TokenCategoryMapping]
    let orderedCategories: [(id: String, displayName: String)]
    let recentTokens: Set<String>
    let addedDates: [String: String]
}

nonisolated struct CatalogFilteredProjectionInput {
    let casks: [Cask]
    let tapCasks: [Cask]
    let retiredCasks: [Cask]
    let library: CatalogLibrarySnapshot
    let selectedSidebar: SidebarSelection
    let searchText: String
    let sortOption: SortOption
    let downloadCounts: [String: Int]
    let recentTokens: Set<String>
    let addedDates: [String: String]
    let installedDates: [String: Date]
    let searchKeys: [String: String]
    let nameRanks: [String: Int]
}

private nonisolated struct LibraryMembership {
    var updatable: [Cask] = []
    var installed: [Cask] = []
    var homebrewInstalled: [Cask] = []

    mutating func add(_ cask: Cask, _ state: CaskLocalState) {
        if state.hasAvailableUpdate { updatable.append(cask) }
        if state.isPresent { installed.append(cask) }
        if state.isHomebrewInstalled { homebrewInstalled.append(cask) }
    }
}

nonisolated enum CatalogProjector {
    static func makeLibrary(
        from input: CatalogLibraryProjectionInput
    ) -> CatalogLibrarySnapshot {
        var library = LibraryMembership()
        var adoptableCasks: [Cask] = []
        var casksByCategory: [String: [Cask]] = [:]

        for cask in input.casks {
            guard let localState = input.localStates[cask.reference] else { continue }
            library.add(cask, localState)
            if localState.isAdoptable, !input.adoptIgnoredTokens.contains(cask.token) {
                adoptableCasks.append(cask)
            }
            // An uninstalled twin would list the official cask's app twice.
            if let mapping = input.categoryMappings[cask.reference],
               !input.officialTwins.contains(cask.reference) || localState.isHomebrewInstalled {
                forEachUniqueCategory(in: mapping) { categoryID in
                    casksByCategory[categoryID, default: []].append(cask)
                }
            }
        }

        for cask in input.installedOnlyCasks {
            guard let localState = input.localStates[cask.reference] else { continue }
            library.add(cask, localState)
        }
        var retiredCasksByCategory: [String: [Cask]] = [:]
        for cask in input.retiredCasks {
            guard let mapping = input.categoryMappings[cask.reference] else { continue }
            forEachUniqueCategory(in: mapping) { categoryID in
                retiredCasksByCategory[categoryID, default: []].append(cask)
            }
        }

        return CatalogLibrarySnapshot(
            updatableCasks: library.updatable,
            installedCasks: library.installed,
            homebrewInstalledCasks: library.homebrewInstalled,
            adoptableCasks: adoptableCasks,
            casksByCategory: casksByCategory,
            categoryCounts: casksByCategory.mapValues(\.count),
            retiredCasksByCategory: retiredCasksByCategory,
            localStates: input.localStates
        )
    }

    /// Without the API catalog every installed token would look removed from Homebrew.
    static func installedOnlyCasks(
        installations: [String: LocalCaskInstallation],
        partition: CatalogPartition
    ) -> [Cask] {
        guard !partition.all.isEmpty else { return [] }
        return installations.values.sorted { $0.token < $1.token }.compactMap { installation in
            let reference = CaskReference.make(token: installation.token, tap: installation.tap)
            guard let cask = partition.byReference[reference] else {
                return Cask.receiptRow(for: installation)
            }
            return cask.isBrowsable ? nil : cask
        }
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
            guard let mapping = input.categoryMappings[cask.reference] else { continue }
            forEachUniqueCategory(in: mapping) { categoryID in
                if casksByCategory[categoryID, default: []].count < sectionSize {
                    casksByCategory[categoryID, default: []].append(cask)
                }
            }
        }

        var sections = [
            BrowseSection(
                title: String(localized: "Most Popular"),
                destination: .discover(.topCharts),
                casks: Array(popularityOrder.lazy.filter { !$0.isFont }.prefix(sectionSize))
            ),
            BrowseSection(
                title: String(localized: "Recently Added"),
                destination: .discover(.recentlyAdded),
                casks: Array(sortedByNewest(
                    input.casks.filter {
                        !$0.isFont && isRecent($0.token, in: input.recentTokens, addedDates: input.addedDates)
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
        let installable = applySort(input.sortOption, to: searched, input: input)
        guard !input.searchText.isEmpty else { return installable }
        // Retired matches always follow installable ones, whatever the sort.
        let retired = applySearch(input.searchText, to: retiredSearchPool(input), keys: input.searchKeys)
        return installable + applySort(input.sortOption, to: retired, input: input)
    }

    private static func retiredSearchPool(_ input: CatalogFilteredProjectionInput) -> [Cask] {
        switch input.selectedSidebar {
        case .discover(.browse): input.retiredCasks
        case .discover: input.retiredCasks.filter { !$0.isFont }
        case let .category(categoryID): input.library.retiredCasksByCategory[categoryID] ?? []
        case .library, .shelfSetup, .maintenance, .tap: []
        }
    }

    static func makeExternallyManaged(
        from input: CatalogFilteredProjectionInput
    ) -> [Cask] {
        let external = input.library.installedCasks.filter { cask in
            guard let state = input.library.localStates[cask.reference] else { return false }
            return !state.isHomebrewInstalled
        }
        let searched = applySearch(input.searchText, to: external, keys: input.searchKeys)
        return applySort(input.sortOption, to: searched, input: input)
    }

    private static func applySidebarFilter(
        _ input: CatalogFilteredProjectionInput
    ) -> [Cask] {
        switch input.selectedSidebar {
        case let .discover(item):
            return discoverCasks(item, input: input)
        case let .library(item):
            return libraryCasks(item, input: input)
        case .shelfSetup, .maintenance:
            return []
        case let .tap(name):
            return input.tapCasks.filter { $0.tap == name }
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
            (keys[cask.reference] ?? cask.searchKey).contains(query)
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
            return casks.sorted { nameAscending($0, $1, ranks: input.nameRanks) }
        case .nameZA:
            return casks.sorted { nameAscending($1, $0, ranks: input.nameRanks) }
        case .recentlyInstalled:
            return casks.sorted { lhs, rhs in
                let lhsDate = input.installedDates[lhs.token]
                let rhsDate = input.installedDates[rhs.token]
                if lhsDate != rhsDate {
                    if let lhsDate, let rhsDate { return lhsDate > rhsDate }
                    return lhsDate != nil
                }
                return nameAscending(lhs, rhs, ranks: input.nameRanks)
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

    /// ICU comparator is the fallback for casks outside the rank snapshot.
    private static func nameAscending(
        _ lhs: Cask,
        _ rhs: Cask,
        ranks: [String: Int]
    ) -> Bool {
        if let lhsRank = ranks[lhs.reference], let rhsRank = ranks[rhs.reference] {
            return lhsRank < rhsRank
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            == .orderedAscending
    }

    private static func forEachUniqueCategory(
        in mapping: TokenCategoryMapping,
        _ body: (CategoryID) -> Void
    ) {
        body(mapping.primary)
        for (index, categoryID) in mapping.secondary.enumerated()
            where categoryID != mapping.primary
                && !mapping.secondary[..<index].contains(categoryID) {
            body(categoryID)
        }
    }

    private static func sortedByDownloads(
        _ casks: [Cask],
        using counts: [String: Int]
    ) -> [Cask] {
        casks.sorted { (counts[$0.reference] ?? 0) > (counts[$1.reference] ?? 0) }
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

extension CatalogProjector {
    private static func discoverCasks(
        _ item: DiscoverItem,
        input: CatalogFilteredProjectionInput
    ) -> [Cask] {
        switch item {
        case .browse:
            return input.searchText.isEmpty ? input.casks : input.casks + input.tapCasks
        case .featured:
            return Array(sortedByDownloads(
                input.casks.filter { !$0.isFont },
                using: input.downloadCounts
            ).prefix(100))
        case .topCharts:
            return input.casks.filter { !$0.isFont }
        case .recentlyAdded:
            return input.casks.filter {
                !$0.isFont && isRecent($0.token, in: input.recentTokens, addedDates: input.addedDates)
            }
        }
    }

    private static func libraryCasks(
        _ item: LibraryItem,
        input: CatalogFilteredProjectionInput
    ) -> [Cask] {
        switch item {
        case .installed:
            return input.library.homebrewInstalledCasks
        case .updates:
            return input.library.updatableCasks
        case .adopt:
            return input.library.adoptableCasks
        case .taps:
            return []
        }
    }
}
