//
//  BrewLockWait.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/11/2026.
//

import Foundation

/// brew's shell locks (a Portable Ruby upgrade, `brew update`) fail at once instead of waiting,
/// so a step that hits one runs again once the other brew lets go.
@MainActor
final class BrewLockWait {
    private let interval: Duration
    private let limit: Duration
    private let operationStore: CaskOperationStore
    private var waitingTokens: Set<String> = []

    init(interval: Duration, limit: Duration, operationStore: CaskOperationStore) {
        self.interval = interval
        self.limit = limit
        self.operationStore = operationStore
    }

    func isWaiting(_ token: String) -> Bool {
        waitingTokens.contains(token)
    }

    func retry(token: String, cancellable: Bool, _ attempt: () async throws -> Void) async throws {
        let giveUp = ContinuousClock.now + limit
        var hasWaited = false
        while true {
            do {
                return try await attempt()
            } catch let error as LocalHomebrewError
                where error.commandFailure?.kind == .brewBusy && ContinuousClock.now < giveUp {
                if !hasWaited {
                    hasWaited = true
                    CrashReporter.breadcrumb("Homebrew.lockWait", data: ["cask": CaskReference.analyticsName(token)])
                }
                try await wait(token: token, cancellable: cancellable)
            }
        }
    }

    /// Reads as Preparing and cancels like a queued step, since no brew process runs meanwhile.
    private func wait(token: String, cancellable: Bool) async throws {
        waitingTokens.insert(token)
        defer { waitingTokens.remove(token) }
        if var progress = operationStore.state(for: token)?.progress {
            progress.phase = progress.action == .updatingHomebrew ? .performing : .preparing
            progress.completedBytes = nil
            progress.totalBytes = nil
            operationStore.send(.updateProgress(progress), for: token)
        }
        operationStore.send(.setCancellable(cancellable), for: token)
        let resume = ContinuousClock.now + interval
        repeat {
            try throwIfCancelled(token)
            try await Task.sleep(for: min(.milliseconds(100), max(.zero, ContinuousClock.now.duration(to: resume))))
        } while ContinuousClock.now < resume
        try throwIfCancelled(token)
        operationStore.send(.setCancellable(false), for: token)
    }

    private func throwIfCancelled(_ token: String) throws {
        if operationStore.state(for: token)?.cancellationRequested == true { throw CancellationError() }
    }
}
