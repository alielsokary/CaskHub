//
//  TapSectionHeader.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import SwiftUI

struct TapSectionHeader: View {
    let tap: TapSummary
    let onViewAll: (() -> Void)?
    let onRemove: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: tap.name)
                .font(CHType.section)
                .foregroundStyle(Color.chTextTitle)
            Text(verbatim: Self.countText(for: tap))
                .font(CHType.countMeta)
                .foregroundStyle(Color.chTextMuted)
            Spacer()
            if let onViewAll {
                Button(action: onViewAll) {
                    Text("View All")
                        .font(CHType.button)
                        .foregroundStyle(Color.chTextBrand)
                }
                .buttonStyle(.plain)
            }
            Menu {
                if let url = Self.repositoryURL(for: tap.remote) {
                    if url.host?.lowercased() == "github.com" {
                        Button("Open on GitHub") { openURL(url) }
                    } else {
                        Button("Open Repository") { openURL(url) }
                    }
                }
                Button("Remove Tap…", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("Tap Actions"))
        }
    }

    static func countText(for tap: TapSummary) -> String {
        let casks = String(localized: "\(tap.caskCount) casks")
        guard tap.formulaCount > 0 else { return casks }
        return "\(casks) · \(String(localized: "\(tap.formulaCount) formulae"))"
    }

    static func repositoryURL(for remote: String?) -> URL? {
        remote.flatMap(URL.web)
    }
}
