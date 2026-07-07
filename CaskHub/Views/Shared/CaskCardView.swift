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

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @State private var showingInfo = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            appInfo
            actionsView
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 0.5)
        )
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

    // MARK: - Header (Icon + Pricing Badge)

    private var headerRow: some View {
        HStack(alignment: .top) {
            iconPlaceholder
            Spacer()
            if let pricingType {
                pricingBadge(pricingType)
            }
            infoButton
        }
    }

    private var infoButton: some View {
        Button {
            showingInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingInfo) {
            CaskInfoPopover(cask: cask)
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

            Text(cask.desc ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 30, alignment: .top)

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

    // MARK: - Actions

    @ViewBuilder
    private var actionsView: some View {
        if let inFlight = localHomebrew.inFlightActions[cask.token] {
            inFlightRow(label: inFlight.inProgressLabel)
        } else if let installation = localHomebrew.installedCasks[cask.token] {
            installedButtons(for: installation)
        } else {
            installButton
        }
    }

    @ViewBuilder
    private func installedButtons(for installation: LocalCaskInstallation) -> some View {
        let showUpdate = localHomebrew.hasAvailableUpdate(
            token: cask.token, remoteVersion: cask.version, autoUpdates: cask.autoUpdates
        )
        let canOpen = !installation.appBundleNames.isEmpty

        HStack(spacing: 8) {
            if canOpen {
                actionButton(systemImage: "play.fill", title: "Open", prominent: false) {
                    localHomebrew.openApp(token: cask.token)
                }
            }
            if showUpdate {
                actionButton(systemImage: "arrow.up.circle.fill", title: "Update", prominent: false) {
                    Task { try? await localHomebrew.upgrade(token: cask.token) }
                }
            }
            Spacer()
            actionButton(systemImage: "trash", title: nil, role: .destructive) {
                showDeleteConfirmation = true
            }
        }
    }

    private func inFlightRow(label: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func actionButton(
        systemImage: String,
        title: String?,
        prominent: Bool = false,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.caption)
                if let title {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: title == nil ? nil : .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, title == nil ? 10 : 0)
            .background(background(prominent: prominent, role: role))
            .foregroundStyle(foreground(prominent: prominent, role: role))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func background(prominent: Bool, role: ButtonRole?) -> AnyShapeStyle {
        if prominent { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(.quaternary)
    }

    private func foreground(prominent: Bool, role: ButtonRole?) -> AnyShapeStyle {
        if prominent { return AnyShapeStyle(.white) }
        if role == .destructive { return AnyShapeStyle(.red) }
        return AnyShapeStyle(.primary)
    }

    // MARK: - Install Button (for not-installed casks)

    private var installButton: some View {
        Button {
            Task { try? await localHomebrew.install(token: cask.token) }
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
                fullToken: "firefox",
                tap: "homebrew/cask",
                name: ["Firefox"],
                desc: "Web browser developed by Mozilla Foundation",
                homepage: "https://www.mozilla.org/firefox/",
                url: "https://download.mozilla.org/firefox.dmg",
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
        .frame(width: 220)

        CaskCardView(
            cask: Cask(
                token: "ledger-live",
                fullToken: "ledger-live",
                tap: "homebrew/cask",
                name: ["Ledger Live"],
                desc: "Manage your crypto assets and hardware wallet securely.",
                homepage: "https://www.ledger.com",
                url: nil,
                version: "2.80.0",
                installed: nil,
                bundleVersion: nil,
                bundleShortVersion: nil,
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
    .environment(LocalHomebrewService())
}
