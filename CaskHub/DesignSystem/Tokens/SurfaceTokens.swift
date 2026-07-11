//
//  SurfaceTokens.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

enum CHRadius {
    static let window: CGFloat = 20
    static let hero: CGFloat = 20
    static let card: CGFloat = 18
    static let iconLg: CGFloat = 26 // hero app icon well
    static let icon: CGFloat = 11 // card app icon well
    static let keycap: CGFloat = 5
    static let badge: CGFloat = 9
    // fields, pills and buttons are capsules
}

/// Fixed content metrics (1360×880 window, 4-card grid).
enum CHSize {
    static let contentWidth: CGFloat = 1086 // hero + grid column: 4×cardWidth + 3×gridGap
    static let cardWidth: CGFloat = 261
    static let cardHeight: CGFloat = 176
    static let heroHeight: CGFloat = 180
}

enum CHSpace {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let gridGap: CGFloat = 14 // cask card grid gap
}
