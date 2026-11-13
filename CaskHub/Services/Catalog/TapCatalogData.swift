//
//  TapCatalogData.swift
//  CaskHub
//
//  Created by Ali Elsokary on 13/11/2026.
//

import Foundation

/// CaskFlow's `tap-categories.json`: categories and icons for registered third-party taps, keyed by `user/repo/token`.
nonisolated struct TapCatalogData: Decodable, Sendable {
    let version: Int
    let generatedDate: String
    let casks: [String: TokenCategoryMapping]
    /// Tap casks that are the same app as an official cask, mapped to its token.
    let sameAs: [String: String]
    let iconCasks: [String]?
}
