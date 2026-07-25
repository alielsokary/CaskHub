//
//  CaskOperationStore.swift
//  CaskHub
//

import Observation

@MainActor
@Observable
final class CaskOperationStore {
    private(set) var states: [String: CaskOperationState] = [:]
    private(set) var updateAllProgress: CaskUpdateAllProgress?

    func state(for token: String) -> CaskOperationState? {
        states[token]
    }

    func send(_ event: CaskOperationEvent, for token: String) {
        let current = states[token]
        let next = CaskOperationStateMachine.transition(from: current, on: event)
        guard next != current else { return }
        states[token] = next
    }

    func setUpdateAllProgress(_ progress: CaskUpdateAllProgress?) {
        guard updateAllProgress != progress else { return }
        updateAllProgress = progress
    }

    func canBeginOperation(for token: String) -> Bool {
        guard let state = states[token] else { return true }
        if case .running = state { return false }
        return true
    }

    var inFlightActions: [String: CaskAction] {
        states.reduce(into: [:]) { result, entry in
            if let action = entry.value.action {
                result[entry.key] = action
            }
        }
    }

    var operationProgress: [String: CaskOperationProgress] {
        states.reduce(into: [:]) { result, entry in
            if let progress = entry.value.progress {
                result[entry.key] = progress
            }
        }
    }

    var failures: [String: CaskOperationFailure] {
        states.reduce(into: [:]) { result, entry in
            if let failure = entry.value.failure {
                result[entry.key] = failure
            }
        }
    }

    var pendingPermissions: [String: Bool] {
        states.reduce(into: [:]) { result, entry in
            if case let .awaitingPermission(force) = entry.value {
                result[entry.key] = force
            }
        }
    }

    var pendingPackageAdoptions: Set<String> {
        Set(states.compactMap { token, state in
            guard case .awaitingPackageAdoption = state else { return nil }
            return token
        })
    }

    var cancellableTokens: Set<String> {
        Set(states.compactMap { token, state in state.canCancel ? token : nil })
    }

    var cancellationRequestedTokens: Set<String> {
        Set(states.compactMap { token, state in
            state.cancellationRequested ? token : nil
        })
    }

    func tokens(offering recovery: CaskRecoveryAction) -> Set<String> {
        Set(failures.compactMap { token, failure in
            failure.recoveries.contains(recovery) ? token : nil
        })
    }

    var status: CaskOperationStatus? {
        CaskOperationStatus.make(
            operations: Array(operationProgress.values),
            updateAll: updateAllProgress
        )
    }
}
