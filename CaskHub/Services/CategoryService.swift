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
    private(set) var isLoaded = false

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
              let catalog = try? JSONDecoder().decode(CaskCategoryData.self, from: data) else {
            return
        }

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
        isLoaded = true
    }

    /// Returns the primary category for a cask token.
    func category(for token: String) -> CategoryID? {
        tokenMappings[token]?.primary
    }

    /// Returns the full mapping (primary + secondary) for a cask token.
    func mapping(for token: String) -> TokenCategoryMapping? {
        tokenMappings[token]
    }

    /// Returns all cask tokens in a category (includes both primary and secondary assignments).
    func tokens(in categoryID: CategoryID) -> Set<String> {
        categoryTokenSets[categoryID] ?? []
    }

    func displayName(for categoryID: CategoryID) -> String {
        categoryDefinitions[categoryID]?.displayName ?? categoryID
    }

    /// Classify a token into a category at runtime (e.g. from on-device ML or remote update).
    func classify(token: String, as categoryID: CategoryID, secondary: [CategoryID] = []) {
        let mapping = TokenCategoryMapping(primary: categoryID, secondary: secondary)
        tokenMappings[token] = mapping
        categoryTokenSets[categoryID, default: []].insert(token)
        for secondaryCat in secondary {
            categoryTokenSets[secondaryCat, default: []].insert(token)
        }
    }
}
