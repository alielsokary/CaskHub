//
//  CategoryService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 27/03/2026.
//

import Foundation
import Observation

typealias CategoryID = String

/// Falls back to the pipeline's English name when the catalog has no
/// `category.<id>` entry yet (e.g. a new category shipped via data sync).
nonisolated func localizedCategoryName(_ id: CategoryID, fallback: String) -> String {
    Bundle.main.localizedString(forKey: "category.\(id)", value: fallback, table: nil)
}

nonisolated struct CategoryDefinition: Codable, Hashable {
    let displayName: String
    let icon: String
}

nonisolated struct TokenCategoryMapping: Codable, Hashable {
    let primary: CategoryID
    let secondary: [CategoryID]
}

nonisolated struct CaskAppIdentity: Decodable, Hashable, Sendable {
    let bundleName: String
    let bundleIdentifier: String
}

nonisolated struct CaskCategoryData: Decodable {
    let version: Int
    let generatedDate: String
    let releaseTag: String?
    let categories: [String: CategoryDefinition]
    let tokenToCategory: [String: TokenCategoryMapping]
    /// Manifest of tokens with an icon on the CaskFlow icons branch, stamped
    /// into the release asset. Absent in pre-2026.07 data → nil.
    let iconTokens: [String]?
    // Optional for releases predating app identity metadata.
    var appIdentities: [String: [CaskAppIdentity]]?
    var metadataUpdatedAt: String?
}

@MainActor
@Observable
final class CategoryService {
    private(set) var categoryDefinitions: [CategoryID: CategoryDefinition] = [:]
    private(set) var tokenMappings: [String: TokenCategoryMapping] = [:]
    private(set) var version: Int = 0
    private(set) var generatedDate: String = ""
    private(set) var releaseTag: String?
    private(set) var iconTokens: Set<String>?
    private(set) var appIdentities: [String: [CaskAppIdentity]] = [:]
    private(set) var metadataUpdatedAt: String?
    private(set) var catalogStateRevision = 0

    var orderedCategories: [(id: CategoryID, definition: CategoryDefinition)] {
        categoryDefinitions
            .sorted { lhs, rhs in
                if lhs.key == "other" { return false }
                if rhs.key == "other" { return true }
                let lhsName = localizedCategoryName(lhs.key, fallback: lhs.value.displayName)
                let rhsName = localizedCategoryName(rhs.key, fallback: rhs.value.displayName)
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
            .map { (id: $0.key, definition: $0.value) }
    }

    /// Off-main decode; never overwrites fresher remote data.
    func loadBundledCategoriesAsync() async {
        guard version == 0 else { return }
        guard let catalog = await Self.decodeBundledCategories(), version == 0
        else { return }
        applyData(catalog)
    }

    @concurrent private static func decodeBundledCategories() async -> CaskCategoryData? {
        guard let url = Bundle.main.url(forResource: "categories", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(CaskCategoryData.self, from: data)
    }

    func refreshFromRemote() async {
        await loadBundledCategoriesAsync()
        guard let remote = await CaskFlowReleases.fetch(CaskCategoryData.self, asset: "categories.json") else { return }
        applyRemoteData(remote)
    }

    func applyRemoteData(_ remote: CaskCategoryData) {
        guard remote.version == version, remote.generatedDate >= generatedDate,
              remote.generatedDate > generatedDate
                || (remote.metadataUpdatedAt ?? "") > (metadataUpdatedAt ?? "") else { return }
        applyData(remote)
    }

    func addingAppIdentities(to casks: [Cask]) -> [Cask] {
        casks.map { cask in
            var enriched = cask
            let names = Set(cask.appArtifactNames + cask.packageAppNameCandidates)
            enriched.catalogBundleIdentifiers = (appIdentities[cask.token] ?? []).filter {
                names.contains($0.bundleName)
                    && $0.bundleIdentifier.range(
                        of: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#, options: .regularExpression
                    ) != nil
            }.map(\.bundleIdentifier)
            return enriched
        }
    }

    func applyData(_ catalog: CaskCategoryData) {
        categoryDefinitions = catalog.categories
        tokenMappings = catalog.tokenToCategory

        version = catalog.version
        generatedDate = catalog.generatedDate
        releaseTag = catalog.releaseTag
        iconTokens = catalog.iconTokens.map(Set.init)
        if let identities = catalog.appIdentities { appIdentities = identities }
        if let updatedAt = catalog.metadataUpdatedAt { metadataUpdatedAt = updatedAt }
        catalogStateRevision &+= 1
    }

    func category(for token: String) -> CategoryID? {
        tokenMappings[token]?.primary
    }

    func displayName(for categoryID: CategoryID) -> String {
        guard let definition = categoryDefinitions[categoryID] else { return categoryID }
        return localizedCategoryName(categoryID, fallback: definition.displayName)
    }
}
