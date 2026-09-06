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
    static let heroTitle = Catalog(scale: 1).hero
    static let section = Font.custom(displayFamily, size: 16).weight(.heavy)

    static let topBarTitle = Font.custom(displayFamily, size: 18).weight(.heavy)

    // UI — everything else
    static let cardTitle = Catalog(scale: 1).title
    static let countMeta = Font.custom(uiFamily, size: 11.5).weight(.semibold) // "3,781 casks" in top bar
    static let field = Font.custom(uiFamily, size: 12.5).weight(.semibold) // search field
    static let navItem = Catalog(scale: 1).navigation
    static let navActive = Catalog(scale: 1).navigationActive
    static let bodySm = Catalog(scale: 1).description
    static let body = Catalog(scale: 1).body
    static let button = Font.custom(uiFamily, size: 12).weight(.heavy)
    static let downloadLabel = Font.custom(uiFamily, size: 10).weight(.semibold)
    static let downloadProgress = Font.custom(uiFamily, size: 9).weight(.semibold)
    static let label = Catalog(scale: 1).label // + .kerning(trackingLabel), uppercase
    static let labelSm = Font.custom(uiFamily, size: 9).weight(.heavy) // row eyebrow

    // Mono — versions, counts, keycaps, status bar
    static let statusMono = Catalog(scale: 1).status

    static let trackingLabel: CGFloat = 2
    static let trackingEyebrow: CGFloat = 2.2
}

/// Text sizing for the catalog and window chrome; display scaling remains controlled by macOS.
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

        var wordmark: Font { .custom(displayFamily, size: 19 * scale).weight(.heavy) }
        var keycap: Font { .custom(monoFamily, size: 9.5 * scale).weight(.bold) }
        var navigation: Font { .custom(uiFamily, size: 13 * scale).weight(.semibold) }
        var navigationActive: Font { .custom(uiFamily, size: 13 * scale).weight(.heavy) }
        var label: Font { .custom(uiFamily, size: 10 * scale).weight(.heavy) }
        var title: Font { .custom(uiFamily, size: 13 * scale).weight(.heavy) }
        var tag: Font { .custom(uiFamily, size: 10 * scale).weight(.bold) }
        var description: Font { .custom(uiFamily, size: 11 * scale).weight(.semibold) }
        var body: Font { .custom(uiFamily, size: 13 * scale).weight(.semibold) }
        var meta: Font { .custom(monoFamily, size: 9.5 * scale) }
        var status: Font { .custom(monoFamily, size: 10.5 * scale) }
        var hero: Font { .custom(displayFamily, size: 28 * scale).weight(.heavy) }
    }
}
