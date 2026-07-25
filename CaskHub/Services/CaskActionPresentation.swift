//
//  CaskActionPresentation.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

nonisolated enum CaskActionAlert: Equatable, Sendable {
    case packageAdoption
    case permission(force: Bool)
    case homebrewMissing(message: String)
    case failure(CaskOperationFailure)
}

nonisolated struct CaskActionPresentation: Equatable, Sendable {
    let localState: CaskLocalState
    let homebrewInstallation: LocalCaskInstallation?
    let operationState: CaskOperationState?

    var activeAction: CaskAction? {
        operationState?.action
    }

    var progress: CaskOperationProgress? {
        operationState?.progress
    }

    var isCanceling: Bool {
        operationState?.cancellationRequested == true
    }

    var canCancel: Bool {
        operationState?.canCancel == true
    }

    var isBusy: Bool {
        activeAction != nil
    }

    var alert: CaskActionAlert? {
        switch operationState {
        case .awaitingPackageAdoption:
            return .packageAdoption
        case let .awaitingPermission(force):
            return .permission(force: force)
        case let .failed(failure) where failure.kind == .homebrewMissing:
            return .homebrewMissing(message: failure.message)
        case let .failed(failure):
            return .failure(failure)
        case .queued, .running, nil:
            return nil
        }
    }
}
