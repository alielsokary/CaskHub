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
                .font(.headline)
                .lineLimit(1)
            if let desc = cask.desc {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    // MARK: - Metadata

    private var metadata: some View {
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
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsControl: some View {
        if let inFlight = localHomebrew.inFlightActions[cask.token] {
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text(inFlight.inProgressLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let installation = localHomebrew.installedCasks[cask.token] {
            installedActionsMenu(for: installation)
        } else {
            installButton
        }
    }

    @ViewBuilder
    private func installedActionsMenu(for installation: LocalCaskInstallation) -> some View {
        let showUpdate = localHomebrew.hasAvailableUpdate(
            token: cask.token, remoteVersion: cask.version, autoUpdates: cask.autoUpdates
        )
        let canOpen = !installation.appBundleNames.isEmpty

        Menu {
            if canOpen {
                Button {
                    localHomebrew.openApp(token: cask.token)
                } label: {
                    Label("Open", systemImage: "play.fill")
                }
            }
            if showUpdate {
                Button {
                    Task { try? await localHomebrew.upgrade(token: cask.token) }
                } label: {
                    Label("Update", systemImage: "arrow.up.circle.fill")
                }
            }
            Divider()
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Uninstall", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Install Button (for not-installed casks)

    private var installButton: some View {
        Button {
            Task { try? await localHomebrew.install(token: cask.token) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.to.line")
                    .font(.caption2)
                Text("Install")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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
}
