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
            // Fixed-width action column + reserved menu slot keep every
            // capsule vertically aligned across rows.
            actionsControl
                .frame(width: 130)
            menuSlot
                .frame(width: 24)
        }
        .padding(.vertical, 4)
        .alert("Uninstall \(cask.displayName)?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                Task { try? await localHomebrew.uninstall(token: cask.token) }
            }
        } message: {
            Text("This will run `brew uninstall --cask \(cask.token)`.")
        }
        .alert("Error", isPresented: hasActionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(localHomebrew.actionErrors[cask.token] ?? "")
        }
    }

    private var hasActionError: Binding<Bool> {
        Binding(
            get: { localHomebrew.actionErrors[cask.token] != nil },
            set: { if !$0 { localHomebrew.clearError(for: cask.token) } }
        )
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
        Text(metaText)
            .font(CHType.statusMono)
            .foregroundStyle(Color.chTextMuted)
    }

    private var metaText: String {
        var parts: [String] = []
        if let downloads { parts.append("↓ \(downloads)") }
        parts.append("v\(cask.displayVersion)")
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private var actionsControl: some View {
        CaskActionsView(cask: cask)
    }

    @ViewBuilder
    private var menuSlot: some View {
        if localHomebrew.installedCasks[cask.token] != nil,
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
            cask: Cask(
                token: "firefox",
                fullToken: nil,
                tap: nil,
                name: ["Firefox"],
                desc: "Web browser developed by Mozilla Foundation",
                homepage: "https://www.mozilla.org/firefox/",
                url: nil,
                version: "125.0",
                installed: nil,
                bundleVersion: nil,
                bundleShortVersion: nil,
                outdated: false,
                deprecated: false,
                disabled: false,
                autoUpdates: true
            ),
            downloads: "1.2M"
        )
    }
    .frame(width: 600)
    .environment(LocalHomebrewService())
    .environment(ImageCacheService())
}
