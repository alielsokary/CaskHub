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
            .caskPermissionAlert(
                cask: cask, service: localHomebrew, isPresented: $showPermissionRequest
            )
            .caskUninstallAlert(
                cask: cask, service: localHomebrew, isPresented: $showUninstallConfirmation
            )
            .caskBrewMissingAlert(isPresented: hasBrewMissingError)
            .caskActionErrorAlert(
                cask: cask, service: localHomebrew, isPresented: hasActionError
            )
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

private extension View {
    func caskPermissionAlert(
        cask: Cask,
        service: LocalHomebrewService,
        isPresented: Binding<Bool>
    ) -> some View {
        onChange(of: service.permissionRequests[cask.token] != nil) { _, isPending in
            if isPending { isPresented.wrappedValue = true }
        }
        .alert("Permission Needed", isPresented: isPresented) {
            Button("Open System Settings") {
                // Request stays pending so adoption resumes when the app becomes active.
                AppManagementPermission.openSystemSettings()
            }
            Button("Adopt Anyway") {
                let useForce = service.permissionRequests[cask.token] == true
                service.cancelPermissionRequest(token: cask.token)
                Task {
                    if useForce {
                        try? await service.adoptReplacing(token: cask.token, bypassPermissionCheck: true)
                    } else {
                        try? await service.adopt(token: cask.token, bypassPermissionCheck: true)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                service.cancelPermissionRequest(token: cask.token)
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
    }

    func caskUninstallAlert(
        cask: Cask,
        service: LocalHomebrewService,
        isPresented: Binding<Bool>
    ) -> some View {
        alert("Uninstall \(cask.displayName)?", isPresented: isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                Task { try? await service.uninstall(token: cask.token) }
            }
        } message: {
            Text("This will run `brew uninstall --cask \(cask.token)`.")
        }
    }

    func caskBrewMissingAlert(isPresented: Binding<Bool>) -> some View {
        alert("Homebrew Not Found", isPresented: isPresented) {
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
    }

    func caskActionErrorAlert(
        cask: Cask,
        service: LocalHomebrewService,
        isPresented: Binding<Bool>
    ) -> some View {
        alert("Error", isPresented: isPresented) {
            if service.adoptReplaceOffers.contains(cask.token) {
                Button("Replace with Homebrew Version") {
                    Task { try? await service.adoptReplacing(token: cask.token) }
                }
            }
            if service.repairOffers.contains(cask.token) {
                Button("Repair & Reinstall") {
                    Task { try? await service.repairReinstalling(token: cask.token) }
                }
            }
            if service.appManagementDenials.contains(cask.token) {
                Button("Open System Settings") {
                    AppManagementPermission.openSystemSettings()
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(service.actionErrors[cask.token] ?? "")
        }
    }
}

extension View {
    func caskActionAlerts(for cask: Cask, showUninstallConfirmation: Binding<Bool>) -> some View {
        modifier(CaskActionAlerts(cask: cask, showUninstallConfirmation: showUninstallConfirmation))
    }
}
