//
//  HomebrewCommandExecutor.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Darwin
import Foundation

nonisolated struct HomebrewCommandRequest: Sendable {
    let token: String
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
}

@MainActor
protocol HomebrewCommandExecuting {
    func execute(
        _ request: HomebrewCommandRequest,
        onStart: @escaping @MainActor @Sendable () -> Void,
        onChunk: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> BrewProcessResult

    @discardableResult
    func cancel(token: String) -> Bool
}

@MainActor
final class SystemHomebrewCommandExecutor: HomebrewCommandExecuting {
    private let processRunner: any BrewProcessRunning
    private var runningProcesses: [String: Process] = [:]
    private static var isExecuting = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    init(processRunner: (any BrewProcessRunning)? = nil) {
        self.processRunner = processRunner ?? SystemBrewProcessRunner()
    }

    func execute(
        _ request: HomebrewCommandRequest,
        onStart: @escaping @MainActor @Sendable () -> Void,
        onChunk: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> BrewProcessResult {
        await Self.acquireGlobalTurn()
        defer { Self.releaseGlobalTurn() }
        try Task.checkCancellation()
        defer { runningProcesses[request.token] = nil }
        return try await processRunner.run(
            executableURL: request.executableURL,
            arguments: request.arguments,
            environment: request.environment,
            onStart: { [weak self] process in
                self?.runningProcesses[request.token] = process
                onStart()
            },
            onChunk: onChunk
        )
    }

    // ponytail: Homebrew uses global locks, so one FIFO is the correct ceiling
    // until CaskHub supports independent Homebrew prefixes at the same time.
    static func acquireGlobalTurn() async {
        guard !isExecuting else {
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        isExecuting = true
    }

    static func releaseGlobalTurn() {
        guard !waiters.isEmpty else {
            isExecuting = false
            return
        }
        waiters.removeFirst().resume()
    }

    func cancel(token: String) -> Bool {
        guard let process = runningProcesses[token] else { return false }
        let pid = process.processIdentifier

        Task { @MainActor [weak self] in
            await Task.detached(priority: .userInitiated) {
                Self.signalTree(pid: pid, signal: SIGINT)
            }.value
            try? await Task.sleep(for: .seconds(5))
            guard self?.runningProcesses[token]?.processIdentifier == pid else {
                return
            }
            await Task.detached(priority: .userInitiated) {
                Self.signalTree(pid: pid, signal: SIGTERM)
            }.value
        }
        return true
    }

    private nonisolated static func signalTree(pid: Int32, signal: Int32) {
        let output = ProcessCapture.capture(
            URL(fileURLWithPath: "/usr/bin/pgrep"),
            arguments: ["-P", "\(pid)"]
        )?.output ?? ""
        for child in output.split(whereSeparator: \.isNewline).compactMap({ Int32($0) }) {
            signalTree(pid: child, signal: signal)
        }
        kill(pid, signal)
    }
}
