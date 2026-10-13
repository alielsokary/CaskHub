//
//  CaskUninstallAlert.swift
//  CaskHub
//
//  Created by Ali Elsokary on 13/10/2026.
//

import AppKit
import SwiftUI

extension CaskActionAlertFactory {
    static func presentUninstallConfirmation(
        for cask: Cask,
        service: LocalHomebrewService,
        in window: NSWindow?,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        guard let window else { return onDismiss() }
        let (alert, actions) = uninstallAlert(for: cask, service: service)
        alert.beginSheetModal(for: window) { response in
            let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            if actions.indices.contains(index) { actions[index]() }
            onDismiss()
        }
    }

    static func uninstallAlert(
        for cask: Cask,
        service: LocalHomebrewService
    ) -> (alert: NSAlert, actions: [() -> Void]) {
        let keepsData = service.zapBlockedByFullDiskAccess
        let removingData = service.zapOnUninstall && !keepsData
        let alert = NSAlert()
        alert.messageText = "Uninstall \(cask.displayName)?"
        if keepsData {
            alert.informativeText = String(localized: .alertUninstallFullDiskAccess)
        } else if removingData {
            alert.informativeText = String(localized: .alertUninstallZap)
        } else {
            alert.informativeText = "This will run:"
        }
        let arguments = service.uninstallArguments(token: cask.token, removingData: removingData)
        let command = NSHostingView(
            rootView: CommandBlock(command: (["brew"] + arguments).joined(separator: " "))
        )
        command.setFrameSize(command.fittingSize)
        alert.accessoryView = command
        let uninstall = alert.addButton(
            withTitle: keepsData ? String(localized: .alertUninstallKeepData) : "Uninstall"
        )
        uninstall.hasDestructiveAction = true
        uninstall.keyEquivalent = ""
        var actions: [() -> Void] = [{
            service.send(keepsData ? .uninstallKeepingData(token: cask.token) : .uninstall(token: cask.token))
        }]
        if keepsData {
            alert.addButton(withTitle: String(localized: "Open System Settings"))
            actions.append { FullDiskAccessPermission.openSystemSettings() }
        }
        alert.addButton(withTitle: "Cancel")
        actions.append {}
        return (alert, actions)
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
