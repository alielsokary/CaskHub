//
//  CaskRowView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import SwiftUI

struct CaskRowView: View {
    let cask: Cask
    var downloads: String?

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            CaskIconView(cask: cask, size: 40)
            appInfo
            Spacer()
            metadata
            actionsControl
                .frame(minWidth: 130, alignment: .trailing)
            menuSlot
                .frame(width: 24)
        }
        .padding(.vertical, 4)
        .caskActionAlerts(for: cask, showUninstallConfirmation: $showDeleteConfirmation)
    }

    // MARK: - App Info

    private var appInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cask.displayName)
                .font(CHType.cardTitle)
                .foregroundStyle(Color.chTextTitle)
                .lineLimit(1)
            if let desc = cask.desc {
                Text(desc)
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextBody)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    // MARK: - Metadata

    private var metadata: some View {
        Text(cask.metaLine(downloads: downloads))
            .font(CHType.statusMono)
            .foregroundStyle(Color.chTextMuted)
    }

    // MARK: - Actions

    private var actionsControl: some View {
        CaskActionsView(cask: cask, fullWidth: false)
    }

    @ViewBuilder
    private var menuSlot: some View {
        if localHomebrew.isInstalled(token: cask.token),
           localHomebrew.inFlightActions[cask.token] == nil {
            installedActionsMenu
        } else {
            Color.clear
        }
    }

    private var installedActionsMenu: some View {
        Menu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Uninstall", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .foregroundStyle(Color.chTextMuted)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

#Preview {
    List {
        CaskRowView(
            cask: .preview(
                token: "firefox",
                name: "Firefox",
                desc: "Web browser developed by Mozilla Foundation",
                version: "125.0",
                autoUpdates: true
            ),
            downloads: "1.2M"
        )
    }
    .frame(width: 600)
    .environment(LocalHomebrewService())
    .environment(ImageCacheService())
}
