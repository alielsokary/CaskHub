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
    var category: (id: String, name: String)?
    var onSelectCategory: ((String) -> Void)?

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @State private var showingInfo = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            descriptionText
            metadataLine
            Spacer(minLength: 2)
            CaskActionsView(cask: cask, onUninstall: canUninstall ? { showDeleteConfirmation = true } : nil)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 15)
        .frame(width: CHSize.cardWidth, height: CHSize.cardHeight, alignment: .topLeading)
        .glassPanel(radius: CHRadius.card)
        .caskActionAlerts(for: cask, showUninstallConfirmation: $showDeleteConfirmation)
    }

    private var canUninstall: Bool {
        localHomebrew.isInstalled(token: cask.token)
    }

    // MARK: - Header (icon well + name + info)

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            CaskIconView(cask: cask, size: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text(cask.displayName)
                    .font(CHType.cardTitle)
                    .foregroundStyle(Color.chTextTitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let category {
                    Button {
                        onSelectCategory?(category.id)
                    } label: {
                        Text(category.name)
                            .font(CHType.tag)
                            .foregroundStyle(Color.chTextBrand)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }

            Spacer(minLength: 4)

            infoButton
        }
        .frame(height: 48, alignment: .top)
    }

    private var infoButton: some View {
        Button {
            showingInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(Color.chTextMuted)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingInfo) {
            CaskInfoPopover(cask: cask)
        }
    }

    // MARK: - Description + metadata

    private var descriptionText: some View {
        Text(cask.desc ?? " ")
            .font(CHType.bodySm)
            .foregroundStyle(Color.chTextBody)
            .lineLimit(2)
            .frame(minHeight: 30, alignment: .top)
    }

    private var metadataLine: some View {
        Text(cask.metaLine(downloads: downloads))
            .font(CHType.metaMono)
            .foregroundStyle(Color.chTextMuted)
    }
}

#Preview {
    ZStack {
        WindowBackdrop()
        HStack {
            CaskCardView(
                cask: .preview(
                    token: "firefox",
                    name: "Firefox",
                    desc: "Web browser developed by Mozilla Foundation",
                    version: "125.0",
                    autoUpdates: true
                ),
                downloads: "1.2M"
            )
            .frame(width: 250)

            CaskCardView(
                cask: .preview(
                    token: "ledger-live",
                    name: "Ledger Live",
                    desc: "Manage your crypto assets and hardware wallet securely.",
                    version: "2.80.0"
                ),
                downloads: "45K"
            )
            .frame(width: 250)
        }
        .padding()
    }
    .environment(LocalHomebrewService())
    .environment(ImageCacheService())
}
