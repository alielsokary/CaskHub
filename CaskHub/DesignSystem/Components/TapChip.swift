//
//  TapChip.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import SwiftUI

/// Marks a cask from a third-party tap, so it is never mistaken for an official twin.
struct TapChip: View {
    let tap: String

    var body: some View {
        Text(verbatim: tap)
            .font(CHType.labelSm)
            .foregroundStyle(Color.chTextBrand)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.chHairline, lineWidth: 1))
            .hoverHint(String(localized: "From the \(tap) tap"))
    }
}

/// The sidebar's tap symbol on cards and rows; hovering names the tap.
struct TapBadge: View {
    let tap: String

    var body: some View {
        Image(systemName: LibraryItem.taps.icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.chTextMuted)
            .contentShape(Rectangle())
            .hoverHint(String(localized: "From the \(tap) tap"))
            .accessibilityLabel(Text(String(localized: "From the \(tap) tap")))
    }
}

private struct ShowsTapBadgesKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Off on the Taps pages, where every cask already sits under its tap.
    var showsTapBadges: Bool {
        get { self[ShowsTapBadgesKey.self] }
        set { self[ShowsTapBadgesKey.self] = newValue }
    }
}
