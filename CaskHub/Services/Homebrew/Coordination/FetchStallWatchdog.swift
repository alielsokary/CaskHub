//
//  FetchStallWatchdog.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/11/2026.
//

import Foundation

/// brew gives its pre-download probe no connect timeout, so an unreachable host can hold a fetch for about 20 minutes.
@MainActor
final class FetchStallWatchdog {
    private let timeout: Duration
    private let operationStore: CaskOperationStore
    private let commandExecutor: any HomebrewCommandExecuting
    private var timers: [String: Task<Void, Never>] = [:]
    private var stalledTokens: Set<String> = []

    init(timeout: Duration, operationStore: CaskOperationStore, commandExecutor: any HomebrewCommandExecuting) {
        self.timeout = timeout
        self.operationStore = operationStore
        self.commandExecutor = commandExecutor
    }

    func observe(_ phase: CaskOperationPhase, token: String) {
        guard phase == .connecting else {
            timers.removeValue(forKey: token)?.cancel()
            return
        }
        guard timers[token] == nil else { return }
        timers[token] = Task { [weak self, timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.giveUp(token: token)
        }
    }

    func classify(_ failure: HomebrewCommandFailure, token: String) -> HomebrewCommandFailure {
        guard stalledTokens.remove(token) != nil else { return failure }
        return HomebrewCommandFailure(
            arguments: failure.arguments,
            exitCode: failure.exitCode,
            diagnostic: failure.diagnostic,
            kind: .networkFailure
        )
    }

    func reset(token: String) {
        timers.removeValue(forKey: token)?.cancel()
        stalledTokens.remove(token)
    }

    private func giveUp(token: String) {
        timers[token] = nil
        guard operationStore.state(for: token)?.progress?.phase == .connecting,
              commandExecutor.cancel(token: token)
        else { return }
        stalledTokens.insert(token)
    }
}
