//
//  ApplicationTerminationCoordinator.swift
//  CaskHub
//
//  Created by Ali Elsokary on 29/07/2026.
//

import AppKit

@MainActor
final class ApplicationTerminationCoordinator: NSObject, NSApplicationDelegate {
    typealias ActiveOperationsProvider = @MainActor () -> Bool
    typealias TerminationRequester = @MainActor () -> Void
    typealias QuitConfirmationPresenter = @MainActor () -> Bool

    private var hasActiveOperations: ActiveOperationsProvider
    private let requestApplicationTermination: TerminationRequester
    private let presentQuitConfirmation: QuitConfirmationPresenter

    override init() {
        hasActiveOperations = { false }
        requestApplicationTermination = {
            NSApplication.shared.terminate(nil)
        }
        presentQuitConfirmation = {
            let alert = NSAlert()
            alert.messageText = String(localized: "Quit CaskHub?")
            alert.informativeText = String(localized: .alertQuitDuringOperation)
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Quit CaskHub"))
            alert.addButton(withTitle: String(localized: "Keep Running"))
            alert.buttons.first?.hasDestructiveAction = true
            alert.buttons.last?.keyEquivalent = "\u{1b}"
            return CrashReporter.withHangTrackingPaused {
                alert.runModal()
            } == .alertFirstButtonReturn
        }
        super.init()
    }

    init(
        hasActiveOperations: @escaping ActiveOperationsProvider,
        requestApplicationTermination: @escaping TerminationRequester,
        presentQuitConfirmation: @escaping QuitConfirmationPresenter
    ) {
        self.hasActiveOperations = hasActiveOperations
        self.requestApplicationTermination = requestApplicationTermination
        self.presentQuitConfirmation = presentQuitConfirmation
        super.init()
    }

    func configure(hasActiveOperations: @escaping ActiveOperationsProvider) {
        self.hasActiveOperations = hasActiveOperations
    }

    func requestTermination() {
        requestApplicationTermination()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard hasActiveOperations() else {
            return .terminateNow
        }

        return presentQuitConfirmation() ? .terminateNow : .terminateCancel
    }
}
