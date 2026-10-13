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
            .caskActionErrorAlert(cask: cask, service: localHomebrew)
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
            CaskActionAlertFactory.presentAfterUpdate {
                CaskActionAlertFactory.presentUninstallConfirmation(for: cask, service: service, in: NSApp.keyWindow) {
                    isPresented.wrappedValue = false
                }
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
        service: LocalHomebrewService
    ) -> some View {
        onChange(of: failure(for: cask, service: service)) { _, failure in
            guard let failure else { return }
            CaskActionAlertFactory.presentAfterUpdate {
                CaskActionAlertFactory.presentError(
                    failure, for: cask, service: service, in: NSApp.keyWindow ?? NSApp.mainWindow
                )
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
    // A sheet begun inside a SwiftUI update re-enters the AppKit update cycle and can crash on macOS 26+.
    static func presentAfterUpdate(_ present: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { present() }
    }

    static func presentError(
        _ failure: CaskOperationFailure,
        for cask: Cask,
        service: LocalHomebrewService,
        in window: NSWindow?
    ) {
        guard let window else { return }
        let (alert, actions) = errorAlert(for: cask, failure: failure, service: service)
        alert.beginSheetModal(for: window) { response in
            let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            service.send(.dismissFailure(token: cask.token))
            if actions.indices.contains(index) { actions[index]() }
        }
    }

    static func errorAlert(
        for cask: Cask,
        failure: CaskOperationFailure,
        service: LocalHomebrewService
    ) -> (alert: NSAlert, actions: [() -> Void]) {
        let failure = failureForPresentation(failure, cask: cask, service: service)
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

    private static func failureForPresentation(
        _ failure: CaskOperationFailure, cask: Cask, service: LocalHomebrewService
    ) -> CaskOperationFailure {
        guard failure.kind == .applicationConflict else { return failure }
        let owner = service.installationSnapshot.externalApplicationOwners[cask.token]
            ?? service.installationSnapshot.installationIndex.homebrewApplications[cask.token]
        if let app = failure.conflictingApplication, let owner,
           app.standardizedFileURL.path == owner.url.standardizedFileURL.path,
           cask.appArtifactNames.contains(app.lastPathComponent) { return failure }
        let guidance: String
        if let app = failure.conflictingApplication, cask.appArtifactNames.contains(app.lastPathComponent) {
            guidance = String(localized: """
            CaskHub couldn't verify that this copy belongs to \(cask.displayName). \
            Refresh the catalog and try again, or move the existing app out of the installation folder first.
            """)
        } else if let app = failure.conflictingApplication {
            guidance = String(localized: """
            The conflict is with \(app.lastPathComponent), which may be a required app. \
            Adopt or repair that app separately in CaskHub, then retry \(cask.displayName).
            """)
        } else {
            guidance = String(localized: """
            CaskHub couldn't identify which app blocked this installation. \
            Resolve the app conflict in Homebrew before retrying.
            """)
        }
        // A dependency collision cannot be repaired by adopting/replacing the parent.
        return CaskOperationFailure(
            kind: failure.kind,
            message: failure.message + "\n\n" + guidance,
            title: failure.title,
            recoveries: failure.recoveries.subtracting([.adoptExisting, .replaceWithHomebrew]),
            conflictingApplication: failure.conflictingApplication
        )
    }
}

private extension CaskRecoveryAction {
    func canPerform(cask: Cask, service: LocalHomebrewService) -> Bool {
        switch self {
        case .openAppManagementSettings, .openFullDiskAccessSettings:
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
        case .openAppManagementSettings, .openFullDiskAccessSettings: "Open System Settings"
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
        case .openFullDiskAccessSettings:
            FullDiskAccessPermission.openSystemSettings()
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
        let message = switch execution {
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
        guard artifact == .applicationBundle, cask.hasPackageArtifact else { return message }
        return message + "\n\n" + String(localized:
            "Homebrew will also run this app's helper installers, which may request administrator permission."
        )
    }
}

extension View {
    func caskActionAlerts(for cask: Cask, showUninstallConfirmation: Binding<Bool>) -> some View {
        modifier(CaskActionAlerts(cask: cask, showUninstallConfirmation: showUninstallConfirmation))
    }
}
