//
//  ImageCacheService+Categories.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/11/2026.
//

import Foundation

extension ImageCacheService {
    /// Icon sources follow CaskFlow's category data: official icon tokens, tap icons, and tap-to-official aliases.
    func connect(to categories: CategoryService) {
        knownIconTokens = { categories.iconTokens }
        knownTapIconRefs = { categories.tapIconRefs }
        officialAlias = { categories.officialAlias(for: $0) }
        tapDataRevision = { categories.tapDataRevision }
    }
}
