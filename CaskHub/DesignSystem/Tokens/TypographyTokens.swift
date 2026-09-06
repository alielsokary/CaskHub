//
//  TypographyTokens.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

enum CHType {
    static let displayFamily = "Baloo 2"
    static let uiFamily = "Nunito"
    static let monoFamily = "JetBrains Mono"

    // Display — wordmark, screen titles, section heads
    static let wordmark = Font.custom(displayFamily, size: 19).weight(.heavy)
    static let heroTitle = Catalog(scale: 1).hero
    static let section = Font.custom(displayFamily, size: 16).weight(.heavy)

    static let topBarTitle = Font.custom(displayFamily, size: 18).weight(.heavy)

    // UI — everything else
    static let cardTitle = Catalog(scale: 1).title
    static let tag = Catalog(scale: 1).tag
    static let countMeta = Font.custom(uiFamily, size: 11.5).weight(.semibold) // "3,781 casks" in top bar
    static let field = Font.custom(uiFamily, size: 12.5).weight(.semibold) // search field
    static let navItem = Font.custom(uiFamily, size: 13).weight(.semibold)
    static let navActive = Font.custom(uiFamily, size: 13).weight(.heavy)
    static let bodySm = Catalog(scale: 1).description
    static let body = Catalog(scale: 1).body
    static let button = Font.custom(uiFamily, size: 12).weight(.heavy)
    static let downloadLabel = Font.custom(uiFamily, size: 10).weight(.semibold)
    static let downloadProgress = Font.custom(uiFamily, size: 9).weight(.semibold)
    static let label = Font.custom(uiFamily, size: 10).weight(.heavy) // + .kerning(trackingLabel), uppercase
    static let labelSm = Font.custom(uiFamily, size: 9).weight(.heavy) // row eyebrow

    // Mono — versions, counts, keycaps, status bar
    static let metaMono = Catalog(scale: 1).meta
    static let statusMono = Catalog(scale: 1).status
    static let keycap = Font.custom(monoFamily, size: 9.5).weight(.bold)

    static let trackingLabel: CGFloat = 2
    static let trackingEyebrow: CGFloat = 2.2
}

/// A catalog-only preference; display scaling remains controlled by macOS.
enum CatalogTextSize: String, CaseIterable {
    case standard, larger, largest

    var scale: CGFloat {
        switch self {
        case .standard: 1
        case .larger: 1.1
        case .largest: 1.2
        }
    }
}

extension EnvironmentValues {
    @Entry var catalogTextScale: CGFloat = 1
}

extension CHType {
    struct Catalog {
        let scale: CGFloat

        var title: Font { .custom(uiFamily, size: 13 * scale).weight(.heavy) }
        var tag: Font { .custom(uiFamily, size: 10 * scale).weight(.bold) }
        var description: Font { .custom(uiFamily, size: 11 * scale).weight(.semibold) }
        var body: Font { .custom(uiFamily, size: 13 * scale).weight(.semibold) }
        var meta: Font { .custom(monoFamily, size: 9.5 * scale) }
        var status: Font { .custom(monoFamily, size: 10.5 * scale) }
        var hero: Font { .custom(displayFamily, size: 28 * scale).weight(.heavy) }
    }
}
