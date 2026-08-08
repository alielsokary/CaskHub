//
//  CaskOperationState.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated enum CaskRecoveryAction: Hashable, Sendable {
    case replaceWithHomebrew
    case adoptExisting
    case repairAndReinstall
    case forceUninstall
    case openAppManagementSettings
}

nonisolated struct CaskOperationFailure: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case homebrewMissing
        case appManagementDenied
        case adoptionPreflight
        case brewCommand
        case applicationUnavailable
    }

    let kind: Kind
    let message: String
    let recoveries: Set<CaskRecoveryAction>

    init(
        kind: Kind,
        message: String,
        recoveries: Set<CaskRecoveryAction> = []
    ) {
        self.kind = kind
        self.message = message
        self.recoveries = recoveries
    }
}

nonisolated enum CaskOperationState: Equatable, Sendable {
    case queued(CaskAction)
    case running(
        progress: CaskOperationProgress,
        canCancel: Bool,
        cancellationRequested: Bool
    )
    case awaitingPermission(force: Bool)
    case awaitingPackageAdoption
    case failed(CaskOperationFailure)

    var action: CaskAction? {
        switch self {
        case let .queued(action):
            return action
        case let .running(progress, _, _):
            return progress.action
        case .awaitingPermission, .awaitingPackageAdoption, .failed:
            return nil
        }
    }

    var progress: CaskOperationProgress? {
        guard case let .running(progress, _, _) = self else { return nil }
        return progress
    }

    var canCancel: Bool {
        guard case let .running(_, canCancel, cancellationRequested) = self else {
            return false
        }
        return canCancel && !cancellationRequested
    }

    var cancellationRequested: Bool {
        guard case let .running(_, _, requested) = self else { return false }
        return requested
    }

    var failure: CaskOperationFailure? {
        guard case let .failed(failure) = self else { return nil }
        return failure
    }
}

nonisolated enum CaskOperationEvent: Equatable, Sendable {
    case enqueue(CaskAction)
    case begin(CaskOperationProgress, canCancel: Bool)
    case updateProgress(CaskOperationProgress)
    case setCancellable(Bool)
    case requestCancellation
    case awaitPermission(force: Bool)
    case awaitPackageAdoption
    case fail(CaskOperationFailure)
    case clear
}

nonisolated enum CaskOperationStateMachine {
    static func transition(
        from state: CaskOperationState?,
        on event: CaskOperationEvent
    ) -> CaskOperationState? {
        switch event {
        case let .enqueue(action):
            return enqueue(action, from: state)

        case let .begin(progress, canCancel):
            return begin(progress, canCancel: canCancel, from: state)

        case let .updateProgress(progress):
            return updateProgress(progress, in: state)

        case let .setCancellable(canCancel):
            return setCancellable(canCancel, in: state)

        case .requestCancellation:
            return requestCancellation(in: state)

        case let .awaitPermission(force):
            return .awaitingPermission(force: force)

        case .awaitPackageAdoption:
            return .awaitingPackageAdoption

        case let .fail(failure):
            return .failed(failure)

        case .clear:
            return nil
        }
    }

    private static func enqueue(
        _ action: CaskAction,
        from state: CaskOperationState?
    ) -> CaskOperationState? {
        guard state == nil || state?.failure != nil else { return state }
        return .queued(action)
    }

    private static func begin(
        _ progress: CaskOperationProgress,
        canCancel: Bool,
        from state: CaskOperationState?
    ) -> CaskOperationState? {
        guard state == nil || canBegin(from: state) else { return state }
        return .running(
            progress: progress,
            canCancel: canCancel,
            cancellationRequested: false
        )
    }

    private static func updateProgress(
        _ progress: CaskOperationProgress,
        in state: CaskOperationState?
    ) -> CaskOperationState? {
        guard case let .running(current, canCancel, cancellationRequested) = state,
              current.token == progress.token,
              current.action == progress.action
        else { return state }
        return .running(
            progress: progress,
            canCancel: canCancel,
            cancellationRequested: cancellationRequested
        )
    }

    private static func setCancellable(
        _ canCancel: Bool,
        in state: CaskOperationState?
    ) -> CaskOperationState? {
        guard case let .running(progress, _, cancellationRequested) = state else {
            return state
        }
        return .running(
            progress: progress,
            canCancel: canCancel && !cancellationRequested,
            cancellationRequested: cancellationRequested
        )
    }

    private static func requestCancellation(
        in state: CaskOperationState?
    ) -> CaskOperationState? {
        guard case let .running(progress, true, false) = state else {
            return state
        }
        var cancelingProgress = progress
        cancelingProgress.phase = .canceling
        return .running(
            progress: cancelingProgress,
            canCancel: false,
            cancellationRequested: true
        )
    }

    private static func canBegin(from state: CaskOperationState?) -> Bool {
        switch state {
        case .queued, .failed, .awaitingPermission, .awaitingPackageAdoption:
            return true
        case .running, nil:
            return false
        }
    }
}
