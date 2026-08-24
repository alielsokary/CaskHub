//
//  HomebrewMutationCoordinator.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

enum HomebrewMutationRecoveryBehavior: Equatable {
    case finishMutation
    case continueSequence
}

struct HomebrewMutationStep {
    let arguments: [String]
    let environmentOverrides: [String: String]
    let cancellable: Bool
    let recoverIf: (() -> Bool)?
    let recoveryBehavior: HomebrewMutationRecoveryBehavior
}

struct HomebrewMutationSequenceRequest {
    let action: CaskAction
    let token: String
    let displayName: String
    let origin: CaskActionOrigin
    let steps: [HomebrewMutationStep]
    let context: HomebrewMutationContext
}

struct HomebrewMutationCallbacks {
    let refresh: () async -> Void
    let strandedCopyExists: () -> Bool
    let postconditionSatisfied: () -> Bool
}
@MainActor
final class HomebrewMutationCoordinator {
    private let operationStore: CaskOperationStore
    private let commandExecutor: any HomebrewCommandExecuting
    private let brewBinaryProvider: () -> URL?
    private let askpassProvider: @Sendable (String) async throws -> URL
    private let fileManager: FileManager

    private let outputAggregator: BrewOutputAggregator

    init(
        operationStore: CaskOperationStore,
        commandExecutor: any HomebrewCommandExecuting,
        brewBinaryProvider: @escaping () -> URL?,
        askpassProvider: @escaping @Sendable (String) async throws -> URL,
        fileManager: FileManager
    ) {
        self.operationStore = operationStore
        self.commandExecutor = commandExecutor
        self.brewBinaryProvider = brewBinaryProvider
        self.askpassProvider = askpassProvider
        self.fileManager = fileManager
        outputAggregator = BrewOutputAggregator(fileManager: fileManager)
    }

    /// Runs a multi-command workflow as one logical mutation. The current
    /// installation snapshot remains published until every step succeeds, so
    /// consumers never render a transient state between destructive steps.
    func runSequence(
        _ request: HomebrewMutationSequenceRequest,
        callbacks: HomebrewMutationCallbacks
    ) async throws {
        guard operationStore.canBeginOperation(
            request.action,
            for: request.token
        ) else { return }
        try preflightBrewLocation(
            request: request,
            strandedCopyExists: callbacks.strandedCopyExists()
        )
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

        for (index, step) in request.steps.enumerated() {
            if index > 0 { prepareNextStep(request: request) }
            let span = CrashReporter.span(name: step.arguments.first ?? "brew", operation: "brew")
            do {
                try await executeStreaming(
                    token: request.token,
                    arguments: step.arguments,
                    cancellable: step.cancellable,
                    environmentOverrides: step.environmentOverrides
                )
                span.finish()
            } catch {
                let resolution = try await handleFailure(
                    error,
                    request: request,
                    step: step,
                    span: span,
                    callbacks: callbacks
                )
                if resolution == .stopSequence {
                    return
                }
            }
        }

        Analytics.caskActionCompleted(
            request.action,
            token: request.token,
            origin: request.origin
        )
        await callbacks.refresh()
        operationStore.send(.clear, for: request.token)
    }
}

extension HomebrewMutationCoordinator {
    func executeStreaming(
        token: String,
        arguments: [String],
        cancellable: Bool,
        environmentOverrides: [String: String] = [:]
    ) async throws {
        let brewURL = try validateBrewLocation()

        let askpass: URL
        do {
            askpass = try await askpassProvider(token)
        } catch {
            throw AskpassScriptManager.localError(for: error)
        }

        var environment = ProcessInfo.processInfo.environment
        environment.merge(environmentOverrides) { _, override in override }
        // brew 6 ask-mode default prompts on our pty; stdin is nulled, so it EOF-aborts.
        environment["HOMEBREW_NO_ASK"] = "1"
        environment["SUDO_ASKPASS"] = askpass.path

        // defer can't await; remove the script deterministically on both exits.
        let result: BrewProcessResult
        do {
            result = try await commandExecutor.execute(
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
        } catch {
            await AskpassScriptManager.remove(at: askpass)
            throw error
        }
        let userCancelled = FileManager.default.fileExists(
            atPath: AskpassScriptManager.cancellationMarker(for: askpass).path
        )
        await AskpassScriptManager.remove(at: askpass)

        guard result.exitCode != 0 else { return }
        if result.wasTerminatedBySignal,
           operationStore.state(for: token)?.cancellationRequested == true {
            throw CancellationError()
        }
        let diagnostic = HomebrewOutputDiagnostics.make(from: result.output)
        let failure = HomebrewCommandFailure(
            arguments: arguments,
            exitCode: result.exitCode,
            diagnostic: diagnostic,
            machineIsAppleSilicon: HomebrewLocator.isAppleSilicon,
            askpassUserCancelled: userCancelled
        )
        throw LocalHomebrewError.brewCommandFailed(failure)
    }

    private func validateBrewLocation() throws -> URL {
        guard let brewURL = brewBinaryProvider() else {
            throw LocalHomebrewError.brewBinaryNotFound
        }
        guard HomebrewLocator.isCompatible(brewURL: brewURL) else {
            throw LocalHomebrewError.incompatibleBrewPath
        }
        return brewURL
    }

    private func preflightBrewLocation(
        request: HomebrewMutationSequenceRequest,
        strandedCopyExists: Bool
    ) throws {
        do {
            _ = try validateBrewLocation()
        } catch {
            recordFailure(
                token: request.token,
                error: error,
                strandedCopyExists: strandedCopyExists
            )
            recordUnrecoveredFailure(error, request: request, span: nil)
            throw error
        }
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
                    phase: action == .uninstalling || action == .updatingHomebrew
                        ? .performing
                        : .preparing
                ),
                canCancel: false
            ),
            for: token
        )
    }

    func clearOperationResources(token: String) {
        outputAggregator.clear(token: token)
    }

    func consumeBrewOutput(_ output: String, token: String) {
        outputAggregator.ingest(output, token: token) { [weak self] parsed in
            self?.applyParsedOutput(parsed, token: token)
        }
    }

    func awaitPendingOutput() async {
        await outputAggregator.drain()
    }

    func applyParsedOutput(_ parsed: BrewOutputAggregator.Parsed, token: String) {
        guard var progress = operationStore.state(for: token)?.progress,
              progress.phase != .canceling
        else { return }

        let update = parsed.update
        if update.phase == .checkingDownload {
            progress.completedBytes = nil
            progress.totalBytes = nil
        }
        if let bytes = update.byteProgress {
            progress.phase = .downloading
            progress.completedBytes = bytes.completed
            progress.totalBytes = bytes.total
        }
        if update.phase == .usingCachedDownload {
            progress.completedBytes = parsed.cachedDownloadBytes
            progress.totalBytes = parsed.cachedDownloadBytes
        }
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
        strandedCopyExists: Bool,
        title: String? = nil
    ) {
        operationStore.send(
            .fail(CaskOperationFailureFactory.make(
                from: error,
                strandedCopyExists: strandedCopyExists,
                title: title
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

    private func prepareNextStep(request: HomebrewMutationSequenceRequest) {
        outputAggregator.clear(token: request.token)
        operationStore.send(
            .updateProgress(CaskOperationProgress(
                token: request.token,
                displayName: request.displayName,
                action: request.action,
                phase: request.action == .updatingHomebrew ? .performing : .preparing
            )),
            for: request.token
        )
        operationStore.send(.setCancellable(false), for: request.token)
    }

    private func handleFailure(
        _ error: Error,
        request: HomebrewMutationSequenceRequest,
        step: HomebrewMutationStep,
        span: CrashSpan,
        callbacks: HomebrewMutationCallbacks
    ) async throws -> FailureResolution {
        if error is CancellationError {
            span.finish()
            await callbacks.refresh()
            operationStore.send(.clear, for: request.token)
            return .stopSequence
        }
        if let localError = error as? LocalHomebrewError,
           case .brewCommandFailed = localError,
           step.recoverIf?() == true {
            span.finish()
            Analytics.caskActionRecovered(
                request.action,
                token: request.token,
                origin: request.origin
            )
            if step.recoveryBehavior == .finishMutation {
                await callbacks.refresh()
                operationStore.send(.clear, for: request.token)
                return .stopSequence
            }
            return .continueSequence
        }
        if let localError = error as? LocalHomebrewError,
           localError.commandFailure?.kind == .exitNonzeroAfterSuccess,
           request.action != .updatingHomebrew {
            await callbacks.refresh()
            if callbacks.postconditionSatisfied() {
                span.finish()
                Analytics.caskActionRecovered(
                    request.action,
                    token: request.token,
                    origin: request.origin
                )
                operationStore.send(.clear, for: request.token)
                return .stopSequence
            }
        }

        recordUnrecoveredFailure(error, request: request, span: span)
        recordFailure(
            token: request.token,
            error: error,
            strandedCopyExists: callbacks.strandedCopyExists(),
            title: request.action == .updatingHomebrew
                ? String(localized: "Homebrew Update Failed")
                : nil
        )
        if Self.indicatesStateDesync(error) {
            await callbacks.refresh()
        }
        throw error
    }

    private enum FailureResolution: Equatable {
        case continueSequence
        case stopSequence
    }

    private func recordUnrecoveredFailure(
        _ error: Error,
        request: HomebrewMutationSequenceRequest,
        span: CrashSpan?
    ) {
        span?.finish(error: error)
        let localError = error as? LocalHomebrewError
        Analytics.caskActionFailed(
            request.action,
            token: request.token,
            origin: request.origin,
            failureKind: localError?.failureKind
        )
        guard HomebrewIssuePolicy.shouldCapture(
            error,
            action: request.action,
            context: request.context
        ) else { return }
        CrashReporter.capture(error, tags: failureTags(for: request))
    }

    private func failureTags(
        for request: HomebrewMutationSequenceRequest
    ) -> [String: String] {
        var tags = request.context.telemetryTags
        tags["brew.action"] = request.action.identifier
        tags["brew.cask"] = request.token
        tags["brew.origin"] = request.origin.rawValue
        if operationStore.state(for: request.token)?.cancellationRequested == true {
            tags["brew.cancellation_requested"] = "true"
        }
        return tags
    }

    /// Brew disagreeing about install state means the snapshot is stale.
    private static func indicatesStateDesync(_ error: Error) -> Bool {
        guard case let LocalHomebrewError.brewCommandFailed(failure) = error else {
            return false
        }
        return failure.kind == .notInstalled
    }

}
