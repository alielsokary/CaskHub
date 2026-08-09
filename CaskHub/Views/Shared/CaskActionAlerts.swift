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
            Text(String(
                localized: "alert.adopt.packageInstaller",
                defaultValue: """
                \(cask.displayName) was installed using a package outside Homebrew. \
                Adopting it will download and run Homebrew's package installer again, \
                which may replace the existing application. After it finishes, \
                Homebrew will manage the installation.
                """,
                comment: "Alert body before adopting an app installed via pkg installer"
            ))
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
            Text(String(
                localized: "alert.appManagementNeeded",
                defaultValue: """
                macOS only lets CaskHub modify other apps once you grant it the \
                App Management permission, and adopting \(cask.displayName) may \
                need to do that. Enable CaskHub under System Settings → Privacy \
                & Security → App Management (a system notification may also \
                offer it), then come back — the adoption will finish on its own.
                """,
                comment: "Alert body asking for the App Management permission before adoption"
            ))
        }
    }

    func caskUninstallAlert(
        cask: Cask,
        service: LocalHomebrewService,
        isPresented: Binding<Bool>
    ) -> some View {
        onChange(of: isPresented.wrappedValue) { _, show in
            guard show else { return }
            guard let window = NSApp.keyWindow else {
                isPresented.wrappedValue = false
                return
            }
            let alert = CaskActionAlertFactory.uninstallAlert(for: cask)
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    service.send(.uninstall(token: cask.token))
                }
                isPresented.wrappedValue = false
            }
        }
    }

    func caskBrewMissingAlert(isPresented: Binding<Bool>) -> some View {
        alert("Homebrew Not Found", isPresented: isPresented) {
            Button("Go to brew.sh") {
                NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(
                localized: "alert.homebrewMissing",
                defaultValue: """
                CaskHub uses Homebrew to install and manage apps, and it doesn't \
                seem to be installed on this Mac. Install it from brew.sh, then \
                come back. CaskHub will pick it up automatically.
                """,
                comment: "Alert body when no Homebrew installation is detected"
            ))
        }
    }

    func caskActionErrorAlert(
        cask: Cask,
        service: LocalHomebrewService,
        isPresented: Binding<Bool>
    ) -> some View {
        onChange(of: isPresented.wrappedValue) { _, show in
            guard show else { return }
            guard let window = NSApp.keyWindow,
                  let failure = failure(for: cask, service: service) else {
                isPresented.wrappedValue = false
                return
            }
            let (alert, actions) = CaskActionAlertFactory.errorAlert(
                for: cask, failure: failure, service: service
            )
            alert.beginSheetModal(for: window) { response in
                let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                if actions.indices.contains(index) { actions[index]() }
                isPresented.wrappedValue = false
            }
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

@MainActor
enum CaskActionAlertFactory {
    static func uninstallAlert(for cask: Cask) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Uninstall \(cask.displayName)?"
        alert.informativeText = "This will run:"
        let command = NSHostingView(
            rootView: CommandBlock(command: "brew uninstall --cask \(cask.token)")
        )
        command.setFrameSize(command.fittingSize)
        alert.accessoryView = command
        let uninstall = alert.addButton(withTitle: "Uninstall")
        uninstall.hasDestructiveAction = true
        uninstall.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    static func errorAlert(
        for cask: Cask,
        failure: CaskOperationFailure,
        service: LocalHomebrewService
    ) -> (alert: NSAlert, actions: [() -> Void]) {
        let alert = NSAlert()
        alert.messageText = "\(cask.displayName) Failed"
        if failure.message.count <= 500 {
            alert.informativeText = failure.message
        } else {
            let scroll = NSTextView.scrollableTextView()
            if let textView = scroll.documentView as? NSTextView {
                textView.string = failure.message
                textView.isEditable = false
                textView.font = .monospacedSystemFont(
                    ofSize: NSFont.smallSystemFontSize, weight: .regular
                )
                textView.textContainerInset = NSSize(width: 6, height: 6)
            }
            scroll.frame = NSRect(x: 0, y: 0, width: 440, height: 200)
            alert.accessoryView = scroll
        }
        var actions: [() -> Void] = []
        for recovery in CaskRecoveryAction.allCases where failure.recoveries.contains(recovery) {
            alert.addButton(withTitle: recovery.buttonTitle).keyEquivalent = ""
            actions.append { recovery.perform(cask: cask, service: service) }
        }
        alert.addButton(withTitle: "OK")
        actions.append {}
        return (alert, actions)
    }
}

private extension CaskRecoveryAction {
    var buttonTitle: String {
        switch self {
        case .adoptExisting: "Adopt Existing App"
        case .replaceWithHomebrew: "Replace with Homebrew Version"
        case .repairAndReinstall: "Repair & Reinstall"
        case .forceUninstall: "Force Uninstall"
        case .openAppManagementSettings: "Open System Settings"
        }
    }

    @MainActor
    func perform(cask: Cask, service: LocalHomebrewService) {
        switch self {
        case .adoptExisting:
            service.send(.adopt(cask))
        case .replaceWithHomebrew:
            service.send(.replaceWithHomebrew(token: cask.token))
        case .repairAndReinstall:
            service.send(.repairAndReinstall(token: cask.token))
        case .forceUninstall:
            service.send(.repair(token: cask.token))
        case .openAppManagementSettings:
            AppManagementPermission.openSystemSettings()
        }
    }
}

private struct CommandBlock: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: command)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark.circle.fill" : "document.on.document")
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help("Copy Command")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

extension View {
    func caskActionAlerts(for cask: Cask, showUninstallConfirmation: Binding<Bool>) -> some View {
        modifier(CaskActionAlerts(cask: cask, showUninstallConfirmation: showUninstallConfirmation))
    }
}
