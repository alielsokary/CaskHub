//
//  CaskCardView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import SwiftUI

struct CaskCardView: View {
    let cask: Cask
    var downloads: String?
    var pricingType: CaskPricingType?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            appInfo
            installButton
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Header (Icon + Pricing Badge)

    private var headerRow: some View {
        HStack {
            iconPlaceholder
            Spacer()
            if let pricingType {
                pricingBadge(pricingType)
            }
        }
    }

    private var iconPlaceholder: some View {
        CaskIconView(cask: cask, size: 44)
    }

    private func pricingBadge(_ type: CaskPricingType) -> some View {
        Text(type.rawValue)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(type.badgeColor.opacity(0.15))
            .foregroundStyle(type.badgeColor)
            .clipShape(Capsule())
    }

    // MARK: - App Info (Name + Description)

    private var appInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(cask.displayName)
                .font(.headline)
                .lineLimit(1)

            if let desc = cask.desc {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(minHeight: 30, alignment: .top)
            }

            metadataRow
        }
    }

    // MARK: - Metadata (Downloads + Version)

    private var metadataRow: some View {
        HStack(spacing: 12) {
            if let downloads {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.to.line")
                    Text(downloads)
                }
            }
            HStack(spacing: 3) {
                Image(systemName: "tag")
                Text("v\(cask.displayVersion)")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    // MARK: - Install Button

    private var installButton: some View {
        Button {
            // Install action — wired up in Phase 5
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.to.line")
                    .font(.caption)
                Text("Install")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack {
        CaskCardView(
            cask: Cask(
                token: "firefox",
                name: ["Firefox"],
                desc: "Web browser developed by Mozilla Foundation",
                homepage: "https://www.mozilla.org/firefox/",
                url: nil,
                version: "125.0",
                installed: nil,
                outdated: false,
                deprecated: false,
                disabled: false,
                autoUpdates: true
            ),
            downloads: "1.2M"
        )
        .frame(width: 220)

        CaskCardView(
            cask: Cask(
                token: "ledger-live",
                name: ["Ledger Live"],
                desc: "Manage your crypto assets and hardware wallet securely.",
                homepage: "https://www.ledger.com",
                url: nil,
                version: "2.80.0",
                installed: nil,
                outdated: false,
                deprecated: false,
                disabled: false,
                autoUpdates: nil
            ),
            downloads: "45K"
        )
        .frame(width: 220)
    }
    .padding()
}
