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
            .caskPackageAdoptionAlert(
                cask: cask, service: localHomebrew, isPresented: hasPackageAdoptionRequest
            )
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

    private var actionAlert: CaskActionAlert? {
        localHomebrew.actionAlert(for: cask.token)
    }

    private var hasBrewMissingError: Binding<Bool> {
        Binding(
            get: {
                guard case .homebrewMissing = actionAlert else { return false }
                return true
            },
            set: {
                if !$0 { localHomebrew.send(.dismissFailure(token: cask.token)) }
            }
        )
    }

    private var hasPackageAdoptionRequest: Binding<Bool> {
        Binding(
            get: {
                guard case .packageAdoption = actionAlert else { return false }
                return true
            },
            set: {
                if !$0 {
                    localHomebrew.send(.cancelPackageAdoption(token: cask.token))
                }
            }
        )
    }

    private var hasActionError: Binding<Bool> {
        Binding(
            get: {
                guard case .failure = actionAlert else { return false }
                return true
            },
            set: {
                if !$0 { localHomebrew.send(.dismissFailure(token: cask.token)) }
            }
        )
    }
}

private extension View {
    func caskPackageAdoptionAlert(
        cask: Cask,
        service: LocalHomebrewService,
        isPresented: Binding<Bool>
    ) -> some View {
        alert("Adopt \(cask.displayName)?", isPresented: isPresented) {
            Button("Cancel", role: .cancel) {
                service.send(.cancelPackageAdoption(token: cask.token))
            }
            Button("Adopt") {
                service.send(.confirmPackageAdoption(token: cask.token))
            }
        } message: {
            Text("""
            \(cask.displayName) was installed using a package outside Homebrew. \
            Adopting it will download and run Homebrew's package installer again, \
            which may replace the existing application. After it finishes, \
            Homebrew will manage the installation.
            """)
        }
    }

    func caskPermissionAlert(
        cask: Cask,
        service: LocalHomebrewService,
        isPresented: Binding<Bool>
    ) -> some View {
        onChange(of: permissionForce(for: cask, service: service)) { _, force in
            if force != nil { isPresented.wrappedValue = true }
        }
        .alert("Permission Needed", isPresented: isPresented) {
            Button("Open System Settings") {
                // Request stays pending so adoption resumes when the app becomes active.
                AppManagementPermission.openSystemSettings()
            }
            Button("Adopt Anyway") {
                let useForce = permissionForce(for: cask, service: service) == true
                service.send(.adoptAnyway(token: cask.token, force: useForce))
            }
            Button("Cancel", role: .cancel) {
                service.send(.cancelPermission(token: cask.token))
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
                service.send(.uninstall(token: cask.token))
            }
        } message: {
            Text("This will run:\n\n") +
            Text("brew uninstall --cask \(cask.token)")
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
            if failure(for: cask, service: service)?
                .recoveries.contains(.replaceWithHomebrew) == true {
                Button("Replace with Homebrew Version") {
                    service.send(.replaceWithHomebrew(token: cask.token))
                }
            }
            if failure(for: cask, service: service)?
                .recoveries.contains(.repairAndReinstall) == true {
                Button("Repair & Reinstall") {
                    service.send(.repairAndReinstall(token: cask.token))
                }
            }
            if failure(for: cask, service: service)?
                .recoveries.contains(.openAppManagementSettings) == true {
                Button("Open System Settings") {
                    AppManagementPermission.openSystemSettings()
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure(for: cask, service: service)?.message ?? "")
        }
    }

    private func permissionForce(
        for cask: Cask,
        service: LocalHomebrewService
    ) -> Bool? {
        guard case let .permission(force) = service.actionAlert(for: cask.token) else {
            return nil
        }
        return force
    }

    private func failure(
        for cask: Cask,
        service: LocalHomebrewService
    ) -> CaskOperationFailure? {
        guard case let .failure(failure) = service.actionAlert(for: cask.token) else {
            return nil
        }
        return failure
    }
}

extension View {
    func caskActionAlerts(for cask: Cask, showUninstallConfirmation: Binding<Bool>) -> some View {
        modifier(CaskActionAlerts(cask: cask, showUninstallConfirmation: showUninstallConfirmation))
    }
}
