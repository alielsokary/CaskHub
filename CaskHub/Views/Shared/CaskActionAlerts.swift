//
//  CaskActionAlerts.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/07/2026.
//

import SwiftUI

/// The uninstall-confirmation and action-error alerts shared by every view
/// that renders a cask (cards and rows).
private struct CaskActionAlerts: ViewModifier {
    let cask: Cask
    @Binding var showUninstallConfirmation: Bool

    @Environment(LocalHomebrewService.self) private var localHomebrew

    func body(content: Content) -> some View {
        content
            .alert("Uninstall \(cask.displayName)?", isPresented: $showUninstallConfirmation) {
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
}

extension View {
    func caskActionAlerts(for cask: Cask, showUninstallConfirmation: Binding<Bool>) -> some View {
        modifier(CaskActionAlerts(cask: cask, showUninstallConfirmation: showUninstallConfirmation))
    }
}
