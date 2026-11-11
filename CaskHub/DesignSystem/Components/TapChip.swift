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
            .help(String(localized: "From the \(tap) tap"))
    }
}
