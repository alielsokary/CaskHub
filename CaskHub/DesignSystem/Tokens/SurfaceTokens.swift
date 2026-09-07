//
//  SurfaceTokens.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

enum CHRadius {
    static let hero: CGFloat = 20
    static let card: CGFloat = 18
    static let iconLg: CGFloat = 26 // hero app icon well
    static let keycap: CGFloat = 5
    // fields, pills and buttons are capsules
}

/// Catalog content stays bounded while fitting compact windows.
enum CHSize {
    static let catalogInset: CGFloat = 20
    static let contentWidth: CGFloat = 1086 // shared hero and grid width, capped at four columns
    static let minimumCardWidth: CGFloat = 250
    static let maximumCardWidth: CGFloat = 280

    static func catalogWidth(availableWidth: CGFloat) -> CGFloat {
        let available = max(0, min(contentWidth, availableWidth))
        let count = max(1, min(4, Int((available + CHSpace.gridGap) / (minimumCardWidth + CHSpace.gridGap))))
        return min(available, CGFloat(count) * maximumCardWidth + CGFloat(count - 1) * CHSpace.gridGap)
    }

    static let cardHeight: CGFloat = 176
    static let heroHeight: CGFloat = 180
    static let actionCapsuleHeight: CGFloat = 28
    static let listActionWidth: CGFloat = 110
}

enum CHSpace {
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let gridGap: CGFloat = 14 // cask card grid gap
}
