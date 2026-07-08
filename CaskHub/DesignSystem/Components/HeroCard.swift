//
//  HeroCard.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

/// "House Pick" hero card at the top of Browse (design option 3b/3c).
struct HeroCard: View {
    let cask: Cask
    var downloads: String?
    var categoryName: String?

    var body: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 0) {
                Text("✷ HOUSE PICK")
                    .font(CHType.label)
                    .kerning(CHType.trackingEyebrow)
                    .foregroundStyle(Color.chTextBrand)
                    .padding(.bottom, 6)

                Text(cask.displayName)
                    .font(CHType.heroTitle)
                    .foregroundStyle(Color.chTextTitle)

                if let desc = cask.desc {
                    Text(desc)
                        .font(CHType.body)
                        .foregroundStyle(Color.chTextBody)
                        .lineLimit(2)
                        .frame(maxWidth: 520, alignment: .leading)
                        .padding(.top, 5)
                }

                HStack(spacing: 14) {
                    CaskActionsView(cask: cask, fullWidth: false)
                    Text(metaLine)
                        .font(CHType.statusMono)
                        .foregroundStyle(Color.chTextMuted)
                }
                .padding(.top, 14)
            }

            Spacer(minLength: 0)

            CaskIconView(cask: cask, size: 76)
                .frame(width: 104, height: 104)
                .background(
                    RoundedRectangle(cornerRadius: CHRadius.iconLg, style: .continuous)
                        .fill(Color.chSurfaceField)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CHRadius.iconLg, style: .continuous)
                        .strokeBorder(Color.chHairlineStrong, lineWidth: 1)
                )
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        // Fixed footprint from the design mock — never stretches with the window.
        .frame(width: CHSize.contentWidth, height: CHSize.heroHeight)
        .glassPanel(radius: CHRadius.hero, surface: .chSurfaceHero, shadow: .chShadowHero)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let downloads { parts.append("\(downloads) pours") }
        parts.append("v\(cask.displayVersion)")
        if let categoryName { parts.append(categoryName) }
        return parts.joined(separator: " · ")
    }
}
