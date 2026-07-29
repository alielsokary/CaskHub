//
//  ApplicationTerminationCoordinator.swift
//  CaskHub
//
//  Created by Ali Elsokary on 29/07/2026.
//

import AppKit
import Combine

@MainActor
final class ApplicationTerminationCoordinator: NSObject, NSApplicationDelegate, ObservableObject {
    typealias ActiveOperationsProvider = @MainActor () -> Bool
    typealias TerminationRequester = @MainActor () -> Void
    typealias TerminationReplier = @MainActor (Bool) -> Void

    @Published var showsQuitConfirmation = false

    private var hasActiveOperations: ActiveOperationsProvider
    private let requestApplicationTermination: TerminationRequester
    private let replyToApplicationTermination: TerminationReplier
    private var isAwaitingTerminationReply = false

    override init() {
        hasActiveOperations = { false }
        requestApplicationTermination = {
            NSApplication.shared.terminate(nil)
        }
        replyToApplicationTermination = { shouldTerminate in
            NSApplication.shared.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        super.init()
    }

    init(
        hasActiveOperations: @escaping ActiveOperationsProvider,
        requestApplicationTermination: @escaping TerminationRequester,
        replyToApplicationTermination: @escaping TerminationReplier
    ) {
        self.hasActiveOperations = hasActiveOperations
        self.requestApplicationTermination = requestApplicationTermination
        self.replyToApplicationTermination = replyToApplicationTermination
        super.init()
    }

    func configure(hasActiveOperations: @escaping ActiveOperationsProvider) {
        self.hasActiveOperations = hasActiveOperations
    }

    func requestTermination() {
        requestApplicationTermination()
    }

    func keepRunning() {
        finishPendingTermination(shouldTerminate: false)
    }

    func confirmTermination() {
        finishPendingTermination(shouldTerminate: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard hasActiveOperations() else {
            return .terminateNow
        }

        isAwaitingTerminationReply = true
        showsQuitConfirmation = true
        return .terminateLater
    }

    private func finishPendingTermination(shouldTerminate: Bool) {
        guard isAwaitingTerminationReply else { return }

        isAwaitingTerminationReply = false
        showsQuitConfirmation = false
        replyToApplicationTermination(shouldTerminate)
    }
}
