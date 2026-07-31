//
//  HomebrewMutationCoordinator.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

struct HomebrewMutationRequest {
    let action: CaskAction
    let token: String
    let displayName: String
    let arguments: [String]
    let origin: CaskActionOrigin
    let environmentOverrides: [String: String]
}

struct HomebrewMutationCallbacks {
    let refresh: () async -> Void
    let strandedCopyExists: () -> Bool
    let recoverIf: (() -> Bool)?
}

@MainActor
final class HomebrewMutationCoordinator {
    private let operationStore: CaskOperationStore
    private let commandExecutor: any HomebrewCommandExecuting
    private let brewBinaryProvider: () -> URL?
    private let fileManager: FileManager

    private var outputBuffers: [String: String] = [:]
    private var lastProgressUpdates: [String: Date] = [:]

    private static let phaseMarkers = ["==>", "Verifying", "Already downloaded:"]

    init(
        operationStore: CaskOperationStore,
        commandExecutor: any HomebrewCommandExecuting,
        brewBinaryProvider: @escaping () -> URL?,
        fileManager: FileManager
    ) {
        self.operationStore = operationStore
        self.commandExecutor = commandExecutor
        self.brewBinaryProvider = brewBinaryProvider
        self.fileManager = fileManager
    }

    func run(
        _ request: HomebrewMutationRequest,
        callbacks: HomebrewMutationCallbacks
    ) async throws {
        guard operationStore.canBeginOperation(for: request.token) else { return }
        beginOperation(
            request.action,
            token: request.token,
            displayName: request.displayName
        )
        Analytics.caskActionStarted(
            request.action,
            token: request.token,
            origin: request.origin
        )
        defer { clearOperationResources(token: request.token) }

        let span = CrashReporter.span(
            name: request.arguments.first ?? "brew",
            operation: "brew"
        )
        do {
            try await executeStreaming(
                token: request.token,
                arguments: request.arguments,
                cancellable: request.action == .installing,
                environmentOverrides: request.environmentOverrides
            )
            span.finish()
            Analytics.caskActionCompleted(
                request.action,
                token: request.token,
                origin: request.origin
            )
            await callbacks.refresh()
            operationStore.send(.clear, for: request.token)
        } catch {
            try await handleFailure(
                error,
                request: request,
                span: span,
                callbacks: callbacks
            )
        }
    }

    func executeStreaming(
        token: String,
        arguments: [String],
        cancellable: Bool,
        environmentOverrides: [String: String] = [:]
    ) async throws {
        guard let brewURL = brewBinaryProvider() else {
            throw LocalHomebrewError.brewBinaryNotFound
        }

        let askpass = AskpassScriptManager.create(token: token)
        defer {
            if let askpass { AskpassScriptManager.remove(at: askpass) }
        }

        var environment = ProcessInfo.processInfo.environment
        environment.merge(environmentOverrides) { _, override in override }
        if let askpass {
            environment["SUDO_ASKPASS"] = askpass.path
        }

        let result = try await commandExecutor.execute(
            HomebrewCommandRequest(
                token: token,
                executableURL: brewURL,
                arguments: arguments,
                environment: environment
            ),
            onStart: { [self] in
                operationStore.send(.setCancellable(cancellable), for: token)
            },
            onChunk: { [self] text in
                consumeBrewOutput(text, token: token)
            }
        )

        guard result.exitCode != 0 else { return }
        throw LocalHomebrewError.brewCommandFailed(
            args: arguments,
            exitCode: result.exitCode,
            stderr: HomebrewOutputDiagnostics.make(from: result.output)
        )
    }

    func beginOperation(
        _ action: CaskAction,
        token: String,
        displayName: String
    ) {
        clearOperationResources(token: token)
        operationStore.send(
            .begin(
                CaskOperationProgress(
                    token: token,
                    displayName: displayName,
                    action: action,
                    phase: action == .uninstalling ? .performing : .preparing
                ),
                canCancel: false
            ),
            for: token
        )
    }

    func clearOperationResources(token: String) {
        outputBuffers[token] = nil
        lastProgressUpdates[token] = nil
    }

    func consumeBrewOutput(_ output: String, token: String) {
        guard var progress = operationStore.state(for: token)?.progress,
              progress.phase != .canceling
        else { return }

        let buffered = String(((outputBuffers[token] ?? "") + output).suffix(6_000))
        outputBuffers[token] = buffered

        // The pty redraws the progress bar dozens of times per second; parsing
        // the buffer tail for every redraw hangs the main thread. Skipped
        // chunks stay buffered, so the next parse sees their state.
        let hasPhaseMarker = Self.phaseMarkers.contains(where: output.contains)
        if !hasPhaseMarker,
           let lastUpdate = lastProgressUpdates[token],
           Date.now.timeIntervalSince(lastUpdate) < 0.10 {
            return
        }

        let update = BrewProgressParser.parse(buffered)
        if update.phase == .checkingDownload {
            progress.completedBytes = nil
            progress.totalBytes = nil
        }
        applyByteProgress(update, to: &progress, token: token)
        applyCachedDownload(update, to: &progress)
        if let phase = update.phase {
            progress.phase = phase
            if phase == .performing {
                operationStore.send(.setCancellable(false), for: token)
            }
        }

        operationStore.send(.updateProgress(progress), for: token)
    }

    func cancel(token: String) {
        guard operationStore.state(for: token)?.canCancel == true,
              commandExecutor.cancel(token: token)
        else { return }
        operationStore.send(.requestCancellation, for: token)
    }

    func recordFailure(
        token: String,
        error: Error,
        strandedCopyExists: Bool
    ) {
        operationStore.send(
            .fail(CaskOperationFailureFactory.make(
                from: error,
                strandedCopyExists: strandedCopyExists
            )),
            for: token
        )
    }

    func removalSatisfied(
        caskroomEntry: URL?,
        appBundleNames: [String],
        applicationDirectories: [URL]
    ) -> Bool {
        guard let caskroomEntry,
              !fileManager.fileExists(atPath: caskroomEntry.path)
        else { return false }
        return appBundleNames.allSatisfy { name in
            applicationDirectories.allSatisfy { directory in
                !fileManager.fileExists(
                    atPath: directory.appendingPathComponent(name).path
                )
            }
        }
    }

    private func applyByteProgress(
        _ update: BrewProgressParser.Update,
        to progress: inout CaskOperationProgress,
        token: String
    ) {
        guard let bytes = update.byteProgress else { return }
        let now = Date.now
        let shouldPublish = lastProgressUpdates[token].map {
            now.timeIntervalSince($0) >= 0.10
        } ?? true
        guard shouldPublish || bytes.completed >= bytes.total else { return }

        progress.phase = .downloading
        progress.completedBytes = bytes.completed
        progress.totalBytes = bytes.total
        lastProgressUpdates[token] = now
    }

    private func applyCachedDownload(
        _ update: BrewProgressParser.Update,
        to progress: inout CaskOperationProgress
    ) {
        guard update.phase == .usingCachedDownload else { return }
        progress.completedBytes = nil
        progress.totalBytes = nil
        guard let path = update.cachedDownloadPath,
              let attributes = try? fileManager.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value > 0
        else { return }
        progress.completedBytes = size.int64Value
        progress.totalBytes = size.int64Value
    }

    private func handleFailure(
        _ error: Error,
        request: HomebrewMutationRequest,
        span: CrashSpan,
        callbacks: HomebrewMutationCallbacks
    ) async throws {
        if operationStore.state(for: request.token)?.cancellationRequested == true {
            span.finish()
            await callbacks.refresh()
            operationStore.send(.clear, for: request.token)
            return
        }
        if let localError = error as? LocalHomebrewError,
           case .brewCommandFailed = localError,
           callbacks.recoverIf?() == true {
            span.finish()
            Analytics.caskActionRecovered(
                request.action,
                token: request.token,
                origin: request.origin
            )
            await callbacks.refresh()
            operationStore.send(.clear, for: request.token)
            return
        }

        span.finish(error: error)
        CrashReporter.capture(error)
        Analytics.caskActionFailed(
            request.action,
            token: request.token,
            origin: request.origin
        )
        recordFailure(
            token: request.token,
            error: error,
            strandedCopyExists: callbacks.strandedCopyExists()
        )
        throw error
    }

}
