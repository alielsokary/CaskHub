//
//  TypographyTokens.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

// CaskHub typography tokens — ported from the design system (tokens/typography.css).
// Baloo 2 (display), Nunito (UI), JetBrains Mono (data); bundled in Resources/Fonts.

enum CHType {
    static let displayFamily = "Baloo 2"
    static let uiFamily = "Nunito"
    static let monoFamily = "JetBrains Mono"

    // Display — wordmark, screen titles, section heads
    static let wordmark = Font.custom(displayFamily, size: 19).weight(.heavy)
    static let screenTitle = Font.custom(displayFamily, size: 26).weight(.heavy)
    static let heroTitle = Font.custom(displayFamily, size: 28).weight(.heavy)
    static let section = Font.custom(displayFamily, size: 16).weight(.heavy)

    static let topBarTitle = Font.custom(displayFamily, size: 18).weight(.heavy)

    // UI — everything else
    static let cardTitle = Font.custom(uiFamily, size: 13).weight(.heavy)
    static let tag = Font.custom(uiFamily, size: 10).weight(.bold) // card category tag
    static let countMeta = Font.custom(uiFamily, size: 11.5).weight(.semibold) // "3,781 casks" in top bar
    static let field = Font.custom(uiFamily, size: 12.5).weight(.semibold) // search field
    static let navItem = Font.custom(uiFamily, size: 13).weight(.semibold)
    static let navActive = Font.custom(uiFamily, size: 13).weight(.heavy)
    static let bodySm = Font.custom(uiFamily, size: 11).weight(.semibold)
    static let body = Font.custom(uiFamily, size: 13).weight(.semibold)
    static let button = Font.custom(uiFamily, size: 12).weight(.heavy)
    static let label = Font.custom(uiFamily, size: 10).weight(.heavy) // + .kerning(trackingLabel), uppercase

    // Mono — versions, counts, keycaps, status bar
    static let metaMono = Font.custom(monoFamily, size: 9.5)
    static let statusMono = Font.custom(monoFamily, size: 10.5)
    static let keycap = Font.custom(monoFamily, size: 9.5).weight(.bold)

    static let trackingLabel: CGFloat = 2
    static let trackingEyebrow: CGFloat = 2.2
}
