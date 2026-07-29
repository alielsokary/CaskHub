//
//  CaskOperationStore.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Observation

@MainActor
@Observable
final class CaskOperationStore {
    private(set) var states: [String: CaskOperationState] = [:]
    private(set) var isUpdatingAll = false
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

    func beginUpdateAll() -> Bool {
        guard !isUpdatingAll else { return false }
        isUpdatingAll = true
        return true
    }

    func setUpdateAllProgress(_ progress: CaskUpdateAllProgress) {
        guard isUpdatingAll else { return }
        guard updateAllProgress != progress else { return }
        updateAllProgress = progress
    }

    func finishUpdateAll() {
        guard isUpdatingAll || updateAllProgress != nil else { return }
        isUpdatingAll = false
        updateAllProgress = nil
    }

    func canBeginOperation(for token: String) -> Bool {
        guard let state = states[token] else { return true }
        if case .running = state { return false }
        return true
    }

    var pendingPermissions: [String: Bool] {
        states.reduce(into: [:]) { result, entry in
            if case let .awaitingPermission(force) = entry.value {
                result[entry.key] = force
            }
        }
    }

    var hasActiveOperations: Bool {
        isUpdatingAll || states.values.contains { $0.action != nil }
    }

    var status: CaskOperationStatus? {
        CaskOperationStatus.make(
            operations: states.values.compactMap(\.progress),
            updateAll: updateAllProgress
        )
    }
}
