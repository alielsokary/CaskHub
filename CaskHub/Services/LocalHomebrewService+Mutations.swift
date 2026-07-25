//
//  LocalHomebrewService+Mutations.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Foundation

extension LocalHomebrewService {
    /// Classifies a failure once, keeping its message and legal recovery
    /// actions in the same state value.
    /// Stranded detection also consults the filesystem — brew can reword its
    /// errors, but a real .app parked in the Caskroom can't be misread.
    func noteFailure(token: String, error: Error) {
        let message = (error as? LocalHomebrewError)?.errorDescription
            ?? error.localizedDescription
        var kind = CaskOperationFailure.Kind.brewCommand
        var recoveries: Set<CaskRecoveryAction> = []

        switch error {
        case LocalHomebrewError.brewBinaryNotFound:
            kind = .homebrewMissing

        case LocalHomebrewError.appBundleNotFound:
            kind = .applicationUnavailable

        case let LocalHomebrewError.brewCommandFailed(args, _, stderr):
            if LocalHomebrewError.isAppManagementDenial(stderr: stderr) {
                kind = .appManagementDenied
                recoveries.insert(.openAppManagementSettings)
            }
            if LocalHomebrewError.isAdoptMismatch(args: args, stderr: stderr),
               !LocalHomebrewError.isStrandedApp(stderr: stderr) {
                recoveries.insert(.replaceWithHomebrew)
            }
            if LocalHomebrewError.isStrandedApp(stderr: stderr)
                || (args.first == "upgrade" && hasStrandedCopy(token: token)) {
                recoveries.insert(.repairAndReinstall)
            }

        default:
            break
        }

        operationStore.send(
            .fail(CaskOperationFailure(
                kind: kind,
                message: message,
                recoveries: recoveries
            )),
            for: token
        )
    }

    func runMutation(
        _ action: CaskAction,
        token: String,
        args: [String],
        origin: CaskActionOrigin = .individual,
        environmentOverrides: [String: String] = [:],
        recoverIf: (() -> Bool)? = nil
    ) async throws {
        guard operationStore.canBeginOperation(for: token) else { return }
        beginOperation(action, token: token)
        Analytics.caskActionStarted(action, token: token, origin: origin)
        defer { clearOperationResources(token: token) }

        let span = CrashReporter.span(name: args.first ?? "brew", operation: "brew")
        do {
            try await runBrewStreaming(
                token: token,
                args: args,
                cancellable: action == .installing,
                environmentOverrides: environmentOverrides
            )
            span.finish()
            Analytics.caskActionCompleted(action, token: token, origin: origin)
            await refresh()
            operationStore.send(.clear, for: token)
        } catch {
            if await finishCancelledMutationIfNeeded(token: token, span: span) { return }
            if let localError = error as? LocalHomebrewError,
               case .brewCommandFailed = localError,
               recoverIf?() == true {
                span.finish()
                Analytics.caskActionRecovered(action, token: token, origin: origin)
                await refresh()
                operationStore.send(.clear, for: token)
                return
            }
            span.finish(error: error)
            CrashReporter.capture(error)
            Analytics.caskActionFailed(action, token: token, origin: origin)
            noteFailure(token: token, error: error)
            throw error
        }
    }

    private func finishCancelledMutationIfNeeded(token: String, span: CrashSpan) async -> Bool {
        guard operationStore.state(for: token)?.cancellationRequested == true else {
            return false
        }
        span.finish()
        // Homebrew owns its cache and safely resumes partial downloads.
        // Never sweep the shared cache: another brew process may be using it.
        await refresh()
        operationStore.send(.clear, for: token)
        return true
    }

    private func hasStrandedCopy(token: String) -> Bool {
        guard let caskroom = configuredCaskroomURL() else { return false }
        return Self.strandedCopyExists(in: caskroom, token: token, fileManager: fileManager)
    }

    func runBrewStreaming(
        token: String,
        args: [String],
        cancellable: Bool,
        environmentOverrides: [String: String] = [:]
    ) async throws {
        guard let brewURL = brewBinaryProvider() else {
            throw LocalHomebrewError.brewBinaryNotFound
        }

        let askpass = Self.ensureAskpassScript(token: token)
        defer {
            if let askpass { Self.removeAskpassScript(at: askpass) }
        }

        var environment = ProcessInfo.processInfo.environment
        environment.merge(environmentOverrides) { _, override in override }
        if let askpass {
            environment["SUDO_ASKPASS"] = askpass.path
        }

        let service = self
        let result = try await commandExecutor.execute(
            HomebrewCommandRequest(
                token: token,
                executableURL: brewURL,
                arguments: args,
                environment: environment
            ),
            onStart: {
                service.operationStore.send(.setCancellable(cancellable), for: token)
            },
            onChunk: { text in
                service.consumeBrewOutput(text, token: token)
            }
        )

        if result.exitCode != 0 {
            throw LocalHomebrewError.brewCommandFailed(
                args: args,
                exitCode: result.exitCode,
                stderr: Self.diagnosticOutput(from: result.output)
            )
        }
    }

    func beginOperation(_ action: CaskAction, token: String) {
        brewOutputBuffers[token] = nil
        lastProgressUpdates[token] = nil
        operationStore.send(
            .begin(
                CaskOperationProgress(
                    token: token,
                    displayName: displayName(for: token),
                    action: action,
                    phase: action == .uninstalling ? .performing : .preparing
                ),
                canCancel: false
            ),
            for: token
        )
    }

    func clearOperation(token: String) {
        operationStore.send(.clear, for: token)
        clearOperationResources(token: token)
    }

    func clearOperationResources(token: String) {
        brewOutputBuffers[token] = nil
        lastProgressUpdates[token] = nil
    }

    func consumeBrewOutput(_ output: String, token: String) {
        guard var progress = operationStore.state(for: token)?.progress,
              progress.phase != .canceling
        else { return }

        let buffered = String(((brewOutputBuffers[token] ?? "") + output).suffix(6_000))
        brewOutputBuffers[token] = buffered

        let update = BrewProgressParser.parse(buffered)
        if update.phase == .checkingDownload {
            progress.completedBytes = nil
            progress.totalBytes = nil
        }
        if let bytes = update.byteProgress {
            let now = Date()
            let shouldPublish = lastProgressUpdates[token].map {
                now.timeIntervalSince($0) >= 0.10
            } ?? true
            if shouldPublish || bytes.completed >= bytes.total {
                progress.phase = .downloading
                progress.completedBytes = bytes.completed
                progress.totalBytes = bytes.total
                lastProgressUpdates[token] = now
            }
        }
        if update.phase == .usingCachedDownload {
            progress.completedBytes = nil
            progress.totalBytes = nil
            if let path = update.cachedDownloadPath,
               let attributes = try? fileManager.attributesOfItem(atPath: path),
               let size = attributes[.size] as? NSNumber,
               size.int64Value > 0 {
                progress.completedBytes = size.int64Value
                progress.totalBytes = size.int64Value
            }
        }
        if let phase = update.phase {
            progress.phase = phase
            if phase == .performing {
                operationStore.send(.setCancellable(false), for: token)
            }
        }

        operationStore.send(.updateProgress(progress), for: token)
    }

    func repairRemovalSatisfied(
        caskroomEntry: URL?,
        appBundleNames: [String]
    ) -> Bool {
        guard let caskroomEntry,
              !fileManager.fileExists(atPath: caskroomEntry.path)
        else { return false }
        return appBundleNames.allSatisfy { name in
            applicationDirectories.allSatisfy { directory in
                !fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
            }
        }
    }

    private static func diagnosticOutput(from output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 8_192
        guard trimmed.count > limit else { return trimmed }

        let important = trimmed.components(separatedBy: .newlines).filter { line in
            let lowercase = line.lowercased()
            return line.contains("Error:")
                || line.contains("Warning:")
                || lowercase.contains("failed")
                || line.contains("Operation not permitted")
        }
        let importantText = String(important.joined(separator: "\n").prefix(2_000))
        let tail = String(trimmed.suffix(limit - 2_100))
        return importantText.isEmpty ? String(trimmed.suffix(limit)) : importantText + "\n…\n" + tail
    }
}
