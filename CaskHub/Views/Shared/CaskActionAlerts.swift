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
            .caskAdoptionAlert(
                cask: cask,
                service: localHomebrew,
                request: adoptionRequest,
                isPresented: hasAdoptionRequest
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

    private var adoptionRequest: CaskAdoptionRequest? {
        guard case let .adoption(request) = actionAlert else { return nil }
        return request
    }

    private var hasAdoptionRequest: Binding<Bool> {
        Binding(
            get: { adoptionRequest != nil },
            set: {
                if !$0 {
                    localHomebrew.send(.cancelAdoption(token: cask.token))
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
    func caskAdoptionAlert(
        cask: Cask,
        service: LocalHomebrewService,
        request: CaskAdoptionRequest?,
        isPresented: Binding<Bool>
    ) -> some View {
        alert(
            request?.plan.confirmationTitle(for: cask)
                ?? String(localized: .alertAdoptTitle(cask.displayName)),
            isPresented: isPresented
        ) {
            Button("Cancel", role: .cancel) {
                service.send(.cancelAdoption(token: cask.token))
            }
            if let request {
                Button(
                    role: request.plan.versionRelationship == .homebrewOlder
                        ? .destructive
                        : nil
                ) {
                    service.send(.confirmAdoption(request))
                } label: {
                    if let symbol = request.plan.confirmationButtonSymbol {
                        Label(
                            request.plan.confirmationButtonTitle,
                            systemImage: symbol
                        )
                    } else {
                        Text(request.plan.confirmationButtonTitle)
                    }
                }
            }
        } message: {
            Text(request?.plan.confirmationMessage(for: cask) ?? "")
        }
    }

    func caskPermissionAlert(
        cask: Cask,
        service: LocalHomebrewService,
        isPresented: Binding<Bool>
    ) -> some View {
        onChange(of: hasPendingPermission(for: cask, service: service)) { _, pending in
            if pending { isPresented.wrappedValue = true }
        }
        .alert("Permission Needed", isPresented: isPresented) {
            Button("Open System Settings") {
                // Request stays pending so adoption resumes when the app becomes active.
                AppManagementPermission.openSystemSettings()
            }
            Button("Cancel", role: .cancel) {
                service.send(.cancelPermission(token: cask.token))
            }
        } message: {
            Text(.alertAppManagementNeeded(cask.displayName))
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
            let alert = CaskActionAlertFactory.uninstallAlert(for: cask, service: service)
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
            Text(.alertHomebrewMissing)
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

    private func hasPendingPermission(
        for cask: Cask,
        service: LocalHomebrewService
    ) -> Bool {
        service.actionAlert(for: cask.token) == .permission
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
    static func uninstallAlert(for cask: Cask, service: LocalHomebrewService) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Uninstall \(cask.displayName)?"
        alert.informativeText = service.zapOnUninstall
            ? String(localized: .alertUninstallZap)
            : "This will run:"
        let command = NSHostingView(
            rootView: CommandBlock(command: (["brew"] + service.uninstallArguments(token: cask.token)).joined(separator: " "))
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
        alert.messageText = failure.kind == .installationPreflight
            ? String(localized: .alertInstallConflictTitle(cask.displayName))
            : failure.title ?? "\(cask.displayName) Failed"
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
            let canPerform = recovery.canPerform(cask: cask, service: service)
            let button = alert.addButton(withTitle: recovery.buttonTitle)
            button.keyEquivalent = ""
            button.isEnabled = canPerform
            button.toolTip = canPerform
                ? nil
                : String(localized: "Wait for the current action to finish.")
            actions.append { recovery.perform(cask: cask, service: service) }
        }
        alert.addButton(withTitle: "OK")
        actions.append {}
        return (alert, actions)
    }
}

private extension CaskRecoveryAction {
    func canPerform(cask: Cask, service: LocalHomebrewService) -> Bool {
        switch self {
        case .openAppManagementSettings:
            true
        case .adoptExisting, .replaceWithHomebrew:
            service.operationStore.canBeginOperation(.adopting, for: cask.token)
        case .repairAndReinstall:
            service.operationStore.canBeginOperation(.repairing, for: cask.token)
        case .updateHomebrew:
            service.operationStore.canBeginOperation(.updatingHomebrew, for: cask.token)
        case .forceUninstall:
            service.operationStore.canBeginOperation(.uninstalling, for: cask.token)
        }
    }

    var buttonTitle: String {
        switch self {
        case .adoptExisting: "Adopt Existing App"
        case .replaceWithHomebrew: "Replace with Homebrew Version"
        case .repairAndReinstall: "Repair & Reinstall"
        case .updateHomebrew: String(localized: "Update Homebrew")
        case .forceUninstall: "Force Uninstall"
        case .openAppManagementSettings: "Open System Settings"
        }
    }

    @MainActor
    func perform(cask: Cask, service: LocalHomebrewService) {
        switch self {
        case .adoptExisting:
            service.send(.requestAdoption(cask))
        case .replaceWithHomebrew:
            service.send(.requestReplacementAdoption(cask))
        case .repairAndReinstall:
            service.send(.repairAndReinstall(token: cask.token))
        case .updateHomebrew:
            service.send(.updateHomebrew(token: cask.token))
        case .forceUninstall:
            service.send(.repair(token: cask.token))
        case .openAppManagementSettings:
            AppManagementPermission.openSystemSettings()
        }
    }
}

extension CaskAdoptionPlan {
    func confirmationTitle(for cask: Cask) -> String {
        switch operation {
        case .adopt:
            String(localized: .alertAdoptTitle(cask.displayName))
        case .updateAndAdopt:
            String(localized: .alertAdoptUpdateTitle(cask.displayName))
        case .downgradeAndAdopt:
            String(localized: .alertAdoptDowngradeTitle(cask.displayName))
        }
    }

    var confirmationButtonTitle: String {
        switch operation {
        case .adopt: String(localized: .alertAdoptButton)
        case .updateAndAdopt: String(localized: .alertAdoptUpdateButton)
        case .downgradeAndAdopt: String(localized: .alertAdoptDowngradeButton)
        }
    }

    var confirmationButtonSymbol: String? {
        switch operation {
        case .adopt: nil
        case .updateAndAdopt: "arrow.up.circle"
        case .downgradeAndAdopt: "arrow.down.circle"
        }
    }

    func confirmationMessage(for cask: Cask) -> String {
        switch execution {
        case .adoptApplication:
            String(localized: .alertAdoptExistingApplication(cask.displayName))
        case .replaceApplication:
            String(localized: .alertAdoptReplaceApplication(
                cask.displayName,
                homebrewVersion
            ))
        case .installPackage:
            String(localized: .alertAdoptPackageInstaller)
        case .replacePackage:
            String(localized: .alertAdoptReplacePackage)
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
