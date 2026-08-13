//
//  CaskActionPresentation.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

nonisolated enum CaskActionAlert: Equatable, Sendable {
    case adoption(CaskAdoptionRequest)
    case permission
    case homebrewMissing(message: String)
    case failure(CaskOperationFailure)

    static func make(operationState: CaskOperationState?) -> Self? {
        switch operationState {
        case let .awaitingAdoption(request):
            return .adoption(request)
        case .awaitingPermission:
            return .permission
        case let .failed(failure) where failure.kind == .homebrewMissing:
            return .homebrewMissing(message: failure.message)
        case let .failed(failure):
            return .failure(failure)
        case .queued, .running, nil:
            return nil
        }
    }
}

nonisolated struct CaskActionPresentation: Equatable, Sendable {
    let localState: CaskLocalState
    let homebrewInstallation: LocalCaskInstallation?
    let operationState: CaskOperationState?
    let isHomebrewMutationBlocked: Bool

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
        activeAction != nil || isHomebrewMutationBlocked
    }

}
