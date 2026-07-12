//
//  CategoryService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 27/03/2026.
//

import Foundation
import Observation

typealias CategoryID = String

struct CategoryDefinition: Codable, Hashable {
    let displayName: String
    let icon: String
}

struct TokenCategoryMapping: Codable, Hashable {
    let primary: CategoryID
    let secondary: [CategoryID]
}

struct CaskCategoryData: Codable {
    let version: Int
    let generatedDate: String
    /// GitHub release tag (e.g. "caskflow-v2026.07.10"), stamped into the
    /// asset by CaskFlow's release workflow. Absent in older data.
    let releaseTag: String?
    let totalCasks: Int
    let categories: [String: CategoryDefinition]
    let tokenToCategory: [String: TokenCategoryMapping]
}

@MainActor
@Observable
final class CategoryService {
    private(set) var categoryDefinitions: [CategoryID: CategoryDefinition] = [:]
    private(set) var tokenMappings: [String: TokenCategoryMapping] = [:]
    private(set) var categoryTokenSets: [CategoryID: Set<String>] = [:]
    private(set) var version: Int = 0
    private(set) var generatedDate: String = ""
    private(set) var releaseTag: String?

    var orderedCategories: [(id: CategoryID, definition: CategoryDefinition)] {
        categoryDefinitions
            .sorted { lhs, rhs in
                if lhs.key == "other" { return false }
                if rhs.key == "other" { return true }
                return lhs.value.displayName.localizedCaseInsensitiveCompare(rhs.value.displayName) == .orderedAscending
            }
            .map { (id: $0.key, definition: $0.value) }
    }

    func loadCategories() {
        guard let url = Bundle.main.url(forResource: "categories", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(CaskCategoryData.self, from: data)
        else {
            return
        }
        applyData(catalog)
    }

    /// Best-effort fetch of the latest categories.json from CaskFlow's GitHub Releases.
    /// Silent on every failure path — bundled data remains in use.
    /// Schema-version mismatches and older `generatedDate` values are also rejected.
    func refreshFromRemote() async {
        guard let remote = await CaskFlowReleases.fetch(CaskCategoryData.self, asset: "categories.json"),
              remote.version == version,
              remote.generatedDate > generatedDate
        else { return }

        applyData(remote)
    }

    func applyData(_ catalog: CaskCategoryData) {
        categoryDefinitions = catalog.categories
        tokenMappings = catalog.tokenToCategory

        var sets: [CategoryID: Set<String>] = [:]
        for (token, mapping) in catalog.tokenToCategory {
            sets[mapping.primary, default: []].insert(token)
            for secondaryCat in mapping.secondary {
                sets[secondaryCat, default: []].insert(token)
            }
        }
        categoryTokenSets = sets
        version = catalog.version
        generatedDate = catalog.generatedDate
        releaseTag = catalog.releaseTag
    }

    /// Returns the primary category for a cask token.
    func category(for token: String) -> CategoryID? {
        tokenMappings[token]?.primary
    }

    /// Returns all cask tokens in a category (includes both primary and secondary assignments).
    func tokens(in categoryID: CategoryID) -> Set<String> {
        categoryTokenSets[categoryID] ?? []
    }

    func displayName(for categoryID: CategoryID) -> String {
        categoryDefinitions[categoryID]?.displayName ?? categoryID
    }
}
