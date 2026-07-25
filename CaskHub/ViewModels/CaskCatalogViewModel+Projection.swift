//
//  CaskCatalogViewModel+Projection.swift
//  CaskHub
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

    private var libraryCacheKey: CatalogLibraryCacheKey {
        CatalogLibraryCacheKey(
            catalogRevision: catalogRevision,
            installationRevision: localHomebrew.catalogStateRevision,
            categoryRevision: categoryService.catalogStateRevision
        )
    }

    private var librarySnapshot: CatalogLibrarySnapshot {
        libraryCache.value(for: libraryCacheKey) { [casks, categoryService, localHomebrew] in
            var updatableCasks: [Cask] = []
            var installedCasks: [Cask] = []
            var adoptableCasks: [Cask] = []
            for cask in casks {
                if localHomebrew.hasAvailableUpdate(
                    token: cask.token,
                    remoteVersion: cask.version,
                    autoUpdates: cask.autoUpdates
                ) {
                    updatableCasks.append(cask)
                }
                if localHomebrew.isPresent(cask) {
                    installedCasks.append(cask)
                }
                if localHomebrew.isAdoptable(cask) {
                    adoptableCasks.append(cask)
                }
            }
            let catalogTokens = Set(casks.map(\.token))
            let categoryCounts = categoryService.categoryTokenSets.mapValues {
                $0.intersection(catalogTokens).count
            }
            return CatalogLibrarySnapshot(
                updatableCasks: updatableCasks,
                installedCasks: installedCasks,
                adoptableCasks: adoptableCasks,
                categoryCounts: categoryCounts
            )
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
        return browseCache.value(for: key) { makeBrowseSections() }
    }

    private func makeBrowseSections() -> [BrowseSection] {
        let counts = analyticsByPeriod[.days365] ?? [:]
        let popularityOrder = sortedByDownloads(casks, using: counts)
        var casksByCategory: [String: [Cask]] = [:]
        for cask in popularityOrder {
            guard let mapping = categoryService.tokenMappings[cask.token] else { continue }
            for categoryID in Set([mapping.primary] + mapping.secondary)
                where casksByCategory[categoryID, default: []].count < Self.browseSectionSize {
                casksByCategory[categoryID, default: []].append(cask)
            }
        }

        let recentTokens = recentlyAdded.recentTokens(within: recentlyAddedWindow.rawValue)
        var sections = [
            BrowseSection(
                title: "Most Popular",
                destination: .discover(.topCharts),
                casks: Array(popularityOrder.prefix(Self.browseSectionSize))
            ),
            BrowseSection(
                title: "Recently Added",
                destination: .discover(.recentlyAdded),
                casks: Array(sortedByNewest(casks.filter {
                    recentTokens.contains($0.token)
                }).prefix(Self.browseSectionSize))
            )
        ]
        for entry in categoryService.orderedCategories where entry.id != "other" {
            sections.append(BrowseSection(
                title: entry.definition.displayName,
                destination: .category(entry.id),
                casks: casksByCategory[entry.id] ?? []
            ))
        }
        return sections.filter { !$0.casks.isEmpty }
    }

    // MARK: - Filtered Casks

    var filteredCasks: [Cask] {
        let key = FilteredCatalogCacheKey(
            library: libraryCacheKey,
            recentlyAddedRevision: recentlyAdded.catalogStateRevision,
            analyticsPeriod: analyticsPeriod,
            recentlyAddedWindow: recentlyAddedWindow,
            selectedSidebar: selectedSidebar,
            searchText: searchText,
            sortOption: sortOption
        )
        return filteredCache.value(for: key) {
            let sidebarFiltered = applySidebarFilter(to: casks)
            let searched = applySearch(to: sidebarFiltered)
            return applySort(to: searched)
        }
    }

    private func applySidebarFilter(to casks: [Cask]) -> [Cask] {
        switch selectedSidebar {
        case .discover(.browse):
            return casks
        case .discover(.featured):
            return Array(sortedByDownloads(casks, using: downloadCounts).prefix(100))
        case .discover(.topCharts):
            return casks
        case .discover(.recentlyAdded):
            let recentTokens = recentlyAdded.recentTokens(within: recentlyAddedWindow.rawValue)
            return casks.filter { recentTokens.contains($0.token) }
        case .library(.installed):
            return installedCasks
        case .library(.updates):
            return updatableCasks
        case .library(.adopt):
            return adoptableCasks
        case let .category(categoryID):
            let tokens = categoryService.tokens(in: categoryID)
            return casks.filter { tokens.contains($0.token) }
        }
    }

    private func applySearch(to casks: [Cask]) -> [Cask] {
        guard !searchText.isEmpty else { return casks }
        let query = searchText.lowercased()
        return casks.filter { cask in
            cask.displayName.lowercased().contains(query)
                || cask.token.lowercased().contains(query)
                || (cask.desc?.lowercased().contains(query) ?? false)
        }
    }

    private func sortedByDownloads(
        _ source: [Cask],
        using counts: [String: Int]
    ) -> [Cask] {
        source.sorted { (counts[$0.token] ?? 0) > (counts[$1.token] ?? 0) }
    }

    private func sortedByNewest(_ source: [Cask]) -> [Cask] {
        source.sorted {
            (recentlyAdded.addedDate(for: $0.token) ?? "")
                > (recentlyAdded.addedDate(for: $1.token) ?? "")
        }
    }

    private func sortedByRecentlyInstalled(_ source: [Cask]) -> [Cask] {
        source.sorted { lhs, rhs in
            let lhsDate = localHomebrew.installedCasks[lhs.token]?.installedAt
            let rhsDate = localHomebrew.installedCasks[rhs.token]?.installedAt
            if lhsDate != rhsDate {
                if let lhsDate, let rhsDate { return lhsDate > rhsDate }
                return lhsDate != nil
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                == .orderedAscending
        }
    }

    private func applySort(to casks: [Cask]) -> [Cask] {
        switch sortOption {
        case .mostPopular:
            return sortedByDownloads(casks, using: downloadCounts)
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
            return sortedByRecentlyInstalled(casks)
        case .newest:
            return sortedByNewest(casks)
        case .oldest:
            return casks.sorted {
                (recentlyAdded.addedDate(for: $0.token) ?? "9999")
                    < (recentlyAdded.addedDate(for: $1.token) ?? "9999")
            }
        }
    }
}
