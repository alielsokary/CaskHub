//
//  CaskHubCommands.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/08/2026.
//

import AppKit
import SwiftUI

enum CaskHubWindowID {
    static let main = "main"
    static let help = "help"
}

extension FocusedValues {
    @Entry var catalogViewMode: Binding<ViewMode>?
    @Entry var sidebarVisibility: Binding<NavigationSplitViewVisibility>?
}

enum CaskHubViewCommand {
    static func sidebarTitle(for visibility: NavigationSplitViewVisibility) -> String {
        visibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar"
    }

    static func sidebarVisibility(
        afterToggling visibility: NavigationSplitViewVisibility
    ) -> NavigationSplitViewVisibility {
        visibility == .detailOnly ? .all : .detailOnly
    }
}

struct CaskHubApplicationCommands: Commands {
    let updater: UpdaterService

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button {
                NSApp.orderFrontStandardAboutPanel(nil)
            } label: {
                Label("About CaskHub", systemImage: "info.circle")
            }

            CheckForUpdatesView(updater: updater)
        }
    }
}

struct CaskHubViewCommands: Commands {
    @FocusedBinding(\.catalogViewMode) private var viewMode
    @FocusedBinding(\.sidebarVisibility) private var sidebarVisibility

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button(sidebarTitle) {
                guard let sidebarVisibility else { return }
                self.sidebarVisibility = CaskHubViewCommand.sidebarVisibility(
                    afterToggling: sidebarVisibility
                )
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .disabled(sidebarVisibility == nil)
        }

        CommandGroup(after: .sidebar) {
            Divider()

            Toggle("Grid", isOn: gridSelection)
                .keyboardShortcut("1", modifiers: .command)
                .disabled(viewMode == nil)

            Toggle("List", isOn: listSelection)
                .keyboardShortcut("2", modifiers: .command)
                .disabled(viewMode == nil)
        }
    }

    private var sidebarTitle: String {
        guard let sidebarVisibility else { return "Show Sidebar" }
        return CaskHubViewCommand.sidebarTitle(for: sidebarVisibility)
    }

    private var gridSelection: Binding<Bool> {
        Binding(
            get: { viewMode == .grid },
            set: { isSelected in
                if isSelected { viewMode = .grid }
            }
        )
    }

    private var listSelection: Binding<Bool> {
        Binding(
            get: { viewMode == .list },
            set: { isSelected in
                if isSelected { viewMode = .list }
            }
        )
    }
}

struct CaskHubHelpCommands: Commands {
    @Binding var selection: HelpTopic
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(HelpTopic.gettingStarted.helpMenuTitle) {
                show(.gettingStarted)
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Button(HelpTopic.homebrew.helpMenuTitle) {
                show(.homebrew)
            }

            Button(HelpTopic.adoption.helpMenuTitle) {
                show(.adoption)
            }

            Button(HelpTopic.installAndUpdate.helpMenuTitle) {
                show(.installAndUpdate)
            }

            Button(HelpTopic.permissions.helpMenuTitle) {
                show(.permissions)
            }

            Divider()

            Link("Report an Issue", destination: CaskHubLinks.issues)
            Link("CaskHub Website", destination: CaskHubLinks.website)
        }
    }

    private func show(_ topic: HelpTopic) {
        selection = topic
        openWindow(id: CaskHubWindowID.help)
    }
}
