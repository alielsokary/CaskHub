//
//  CaskOperationStore.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Observation

/// Per-token Observable identity: a progress tick invalidates one row, not all.
@MainActor
@Observable
final class CaskOperationBox {
    fileprivate(set) var state: CaskOperationState?
}

@MainActor
@Observable
final class CaskOperationStore {
    private(set) var boxes: [String: CaskOperationBox] = [:]
    private(set) var isUpdatingAll = false
    private(set) var updateAllProgress: CaskUpdateAllProgress?

    func state(for token: String) -> CaskOperationState? {
        boxes[token]?.state
    }

    func send(_ event: CaskOperationEvent, for token: String) {
        let box: CaskOperationBox
        if let existing = boxes[token] {
            box = existing
        } else {
            box = CaskOperationBox()
            boxes[token] = box
        }
        let next = CaskOperationStateMachine.transition(from: box.state, on: event)
        guard next != box.state else { return }
        box.state = next
    }

    func beginUpdateAll() -> Bool {
        guard !isUpdatingAll, !isUpdatingHomebrew else { return false }
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
        guard let state = boxes[token]?.state else { return true }
        if case .running = state { return false }
        return true
    }

    func canBeginOperation(_ action: CaskAction, for token: String) -> Bool {
        if action == .updatingHomebrew {
            return !hasActiveOperations
        }
        guard !isUpdatingHomebrew else { return false }
        return canBeginOperation(for: token)
    }

    var isUpdatingHomebrew: Bool {
        boxes.values.contains { $0.state?.action == .updatingHomebrew }
    }

    var pendingPermissions: [String: CaskAdoptionRequest] {
        boxes.reduce(into: [:]) { result, entry in
            if case let .awaitingPermission(request) = entry.value.state {
                result[entry.key] = request
            }
        }
    }

    var hasActiveOperations: Bool {
        isUpdatingAll || boxes.values.contains { $0.state?.action != nil }
    }

    var status: CaskOperationStatus? {
        CaskOperationStatus.make(
            operations: boxes.values.compactMap(\.state?.progress),
            updateAll: updateAllProgress
        )
    }
}
