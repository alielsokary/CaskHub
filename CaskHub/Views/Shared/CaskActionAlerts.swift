//
//  CaskActionAlerts.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/07/2026.
//

import AppKit
import SwiftUI

private struct CaskActionAlerts: ViewModifier {
    let cask: Cask
    @Binding var showUninstallConfirmation: Bool

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @State private var showPermissionRequest = false

    func body(content: Content) -> some View {
        content
            .onChange(of: localHomebrew.permissionRequests[cask.token] != nil) { _, isPending in
                if isPending { showPermissionRequest = true }
            }
            .alert("Permission Needed", isPresented: $showPermissionRequest) {
                Button("Open System Settings") {
                    // Request stays pending — adoption continues automatically
                    // when the user returns with the permission granted.
                    AppManagementPermission.openSystemSettings()
                }
                Button("Adopt Anyway") {
                    let useForce = localHomebrew.permissionRequests[cask.token] == true
                    localHomebrew.cancelPermissionRequest(token: cask.token)
                    Task {
                        if useForce {
                            try? await localHomebrew.adoptReplacing(token: cask.token, bypassPermissionCheck: true)
                        } else {
                            try? await localHomebrew.adopt(token: cask.token, bypassPermissionCheck: true)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    localHomebrew.cancelPermissionRequest(token: cask.token)
                }
            } message: {
                Text("""
                macOS only lets CaskHub modify other apps once you grant it the \
                App Management permission, and adopting \(cask.displayName) may \
                need to do that. Enable CaskHub under System Settings → Privacy \
                & Security → App Management (a system notification may also \
                offer it), then come back — the adoption will finish on its own.
                """)
            }
            .alert("Uninstall \(cask.displayName)?", isPresented: $showUninstallConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Uninstall", role: .destructive) {
                    Task { try? await localHomebrew.uninstall(token: cask.token) }
                }
            } message: {
                Text("This will run `brew uninstall --cask \(cask.token)`.")
            }
            .alert("Homebrew Not Found", isPresented: hasBrewMissingError) {
                Button("Go to brew.sh") {
                    NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("""
                CaskHub uses Homebrew to install and manage apps, and it doesn't \
                seem to be installed on this Mac. Install it from brew.sh, then \
                come back. CaskHub will pick it up automatically.
                """)
            }
            .alert("Error", isPresented: hasActionError) {
                if localHomebrew.adoptReplaceOffers.contains(cask.token) {
                    Button("Replace with Homebrew Version") {
                        Task { try? await localHomebrew.adoptReplacing(token: cask.token) }
                    }
                }
                if localHomebrew.appManagementDenials.contains(cask.token) {
                    Button("Open System Settings") {
                        AppManagementPermission.openSystemSettings()
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(localHomebrew.actionErrors[cask.token] ?? "")
            }
    }

    private var brewIsMissing: Bool {
        localHomebrew.brewVersion == nil
    }

    private var hasBrewMissingError: Binding<Bool> {
        Binding(
            get: { localHomebrew.actionErrors[cask.token] != nil && brewIsMissing },
            set: { if !$0 { localHomebrew.clearError(for: cask.token) } }
        )
    }

    private var hasActionError: Binding<Bool> {
        Binding(
            get: { localHomebrew.actionErrors[cask.token] != nil && !brewIsMissing },
            set: { if !$0 { localHomebrew.clearError(for: cask.token) } }
        )
    }
}

extension View {
    func caskActionAlerts(for cask: Cask, showUninstallConfirmation: Binding<Bool>) -> some View {
        modifier(CaskActionAlerts(cask: cask, showUninstallConfirmation: showUninstallConfirmation))
    }
}
