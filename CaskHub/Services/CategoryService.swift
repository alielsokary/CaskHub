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

struct CaskCategoryData: Codable {
    let version: Int
    let generatedDate: String
    let totalCasks: Int
    let categories: [String: CategoryDefinition]
    let tokenToCategory: [String: String]
}

@MainActor
@Observable
final class CategoryService {
    private(set) var categoryDefinitions: [CategoryID: CategoryDefinition] = [:]
    private(set) var tokenToCategory: [String: CategoryID] = [:]
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
        tokenToCategory = catalog.tokenToCategory

        var sets: [CategoryID: Set<String>] = [:]
        for (token, catID) in catalog.tokenToCategory {
            sets[catID, default: []].insert(token)
        }
        categoryTokenSets = sets
        isLoaded = true
    }

    func category(for token: String) -> CategoryID? {
        tokenToCategory[token]
    }

    func tokens(in categoryID: CategoryID) -> Set<String> {
        categoryTokenSets[categoryID] ?? []
    }

    func displayName(for categoryID: CategoryID) -> String {
        categoryDefinitions[categoryID]?.displayName ?? categoryID
    }

    /// Future hook for Foundation Models on-device classification
    func classify(token: String, as categoryID: CategoryID) {
        tokenToCategory[token] = categoryID
        categoryTokenSets[categoryID, default: []].insert(token)
    }
}
