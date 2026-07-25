//
//  CaskRowView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import AppKit
import SwiftUI

struct CaskRowView: View {
    let cask: Cask
    var downloads: String?

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @State private var showDeleteConfirmation = false
    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 12) {
            CaskIconView(cask: cask, size: 40)
            appInfo
            Spacer()
            metadata
            actionsControl
                .frame(width: CHSize.listActionWidth, alignment: .trailing)
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
        CaskActionsView(
            cask: cask,
            fullWidth: true,
            showsUninstallControl: false,
            usesIconOnlyOpenAndUpdate: true
        )
    }

    private var menuSlot: some View {
        actionsMenu
    }

    private var actionsMenu: some View {
        CaskRowActionsMenuButton(
            showsUpdate: hasAvailableUpdate,
            isBusy: isBusy,
            uninstallAvailability: uninstallAvailability,
            onInfo: {
                DispatchQueue.main.async {
                    showingInfo = true
                }
            },
            onUpdate: {
                Task { try? await localHomebrew.upgrade(token: cask.token) }
            },
            onUninstall: {
                showDeleteConfirmation = true
            }
        )
        .frame(width: 24, height: 24)
        .popover(isPresented: $showingInfo) {
            CaskInfoPopover(cask: cask)
        }
    }

    private var hasAvailableUpdate: Bool {
        localHomebrew.hasAvailableUpdate(
            token: cask.token,
            remoteVersion: cask.version,
            autoUpdates: cask.autoUpdates
        )
    }

    private var uninstallAvailability: CaskUninstallAvailability {
        localHomebrew.uninstallAvailability(for: cask)
    }

    private var isBusy: Bool {
        localHomebrew.inFlightActions[cask.token] != nil
    }
}

private struct CaskRowActionsMenuButton: NSViewRepresentable {
    let showsUpdate: Bool
    let isBusy: Bool
    let uninstallAvailability: CaskUninstallAvailability
    let onInfo: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.image = NSImage(
            systemSymbolName: "ellipsis.circle",
            accessibilityDescription: "More actions"
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        button.contentTintColor = NSColor(Color.chTextMuted)
        button.focusRingType = .none
        button.toolTip = "More actions"
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.setAccessibilityLabel("More actions")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.configuration = self
    }

    @MainActor
    final class Coordinator: NSObject {
        var configuration: CaskRowActionsMenuButton

        init(configuration: CaskRowActionsMenuButton) {
            self.configuration = configuration
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = makeMenu()
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY - 4),
                in: sender
            )
        }

        @objc private func showInfo() {
            configuration.onInfo()
        }

        @objc private func update() {
            configuration.onUpdate()
        }

        @objc private func uninstall() {
            configuration.onUninstall()
        }

        private func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(
                menuItem(
                    title: "Info",
                    systemImage: "info.circle",
                    action: #selector(showInfo)
                )
            )

            if configuration.showsUpdate {
                menu.addItem(
                    menuItem(
                        title: "Update",
                        systemImage: "arrow.clockwise",
                        action: #selector(update),
                        isEnabled: !configuration.isBusy,
                        toolTip: configuration.isBusy
                            ? "Wait for the current action to finish."
                            : nil
                    )
                )
            }

            if configuration.uninstallAvailability != .notApplicable {
                menu.addItem(.separator())
                menu.addItem(uninstallMenuItem())
            }
            return menu
        }

        private func uninstallMenuItem() -> NSMenuItem {
            let reason: String?
            switch configuration.uninstallAvailability {
            case .available:
                reason = configuration.isBusy
                    ? "Wait for the current action to finish."
                    : nil
            case let .unavailable(unavailableReason):
                reason = unavailableReason
            case .notApplicable:
                reason = nil
            }

            return menuItem(
                title: "Uninstall",
                systemImage: "trash",
                action: #selector(uninstall),
                isEnabled: reason == nil,
                toolTip: reason
            )
        }

        private func menuItem(
            title: String,
            systemImage: String,
            action: Selector,
            isEnabled: Bool = true,
            toolTip: String? = nil
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
            item.isEnabled = isEnabled
            item.toolTip = toolTip
            item.setAccessibilityHelp(toolTip)
            return item
        }
    }
}

#if DEBUG
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
#endif
