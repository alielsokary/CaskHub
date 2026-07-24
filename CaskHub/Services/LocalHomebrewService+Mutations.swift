//
//  LocalHomebrewService+Mutations.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Foundation

extension LocalHomebrewService {
    /// Classifies a brew failure into the offer sets the alert UI reads.
    /// Stranded detection also consults the filesystem — brew can reword its
    /// errors, but a real .app parked in the Caskroom can't be misread.
    func noteFailure(token: String, error: Error) {
        guard case let LocalHomebrewError.brewCommandFailed(args, _, stderr) = error else { return }
        if LocalHomebrewError.isAppManagementDenial(stderr: stderr) {
            appManagementDenials.insert(token)
        }
        if LocalHomebrewError.isStrandedApp(stderr: stderr)
            || (args.first == "upgrade" && hasStrandedCopy(token: token)) {
            repairOffers.insert(token)
        }
    }

    func runMutation(
        _ action: CaskAction,
        token: String,
        args: [String],
        origin: CaskActionOrigin = .individual,
        environmentOverrides: [String: String] = [:],
        recoverIf: (() -> Bool)? = nil
    ) async throws {
        guard inFlightActions[token] == nil || inFlightActions[token] == .queued else { return }
        beginOperation(action, token: token)
        actionErrors[token] = nil
        Analytics.caskActionStarted(action, token: token, origin: origin)
        defer { clearOperation(token: token) }

        let span = CrashReporter.span(name: args.first ?? "brew", operation: "brew")
        do {
            try await runBrewStreaming(
                token: token,
                args: args,
                cancellable: action == .installing,
                environmentOverrides: environmentOverrides
            )
            span.finish()
            cancelRequested.remove(token)
            Analytics.caskActionCompleted(action, token: token, origin: origin)
            await refresh()
        } catch {
            if await finishCancelledMutationIfNeeded(token: token, span: span) { return }
            if let localError = error as? LocalHomebrewError,
               case .brewCommandFailed = localError,
               recoverIf?() == true {
                span.finish()
                cancelRequested.remove(token)
                Analytics.caskActionRecovered(action, token: token, origin: origin)
                await refresh()
                return
            }
            span.finish(error: error)
            CrashReporter.capture(error)
            Analytics.caskActionFailed(action, token: token, origin: origin)
            noteFailure(token: token, error: error)
            actionErrors[token] = (error as? LocalHomebrewError)?.errorDescription
                ?? error.localizedDescription
            throw error
        }
    }

    private func finishCancelledMutationIfNeeded(token: String, span: CrashSpan) async -> Bool {
        guard cancelRequested.contains(token) else { return false }
        span.finish()
        cancelRequested.remove(token)
        // Homebrew owns its cache and safely resumes partial downloads.
        // Never sweep the shared cache: another brew process may be using it.
        await refresh()
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
        let result = try await processRunner.run(
            executableURL: brewURL,
            arguments: args,
            environment: environment,
            onStart: { process in
                service.runningProcesses[token] = process
                if cancellable { service.cancellableDownloads.insert(token) }
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
        inFlightActions[token] = action
        brewOutputBuffers[token] = nil
        lastProgressUpdates[token] = nil
        operationProgress[token] = CaskOperationProgress(
            token: token,
            displayName: displayName(for: token),
            action: action,
            phase: action == .uninstalling ? .performing : .preparing
        )
    }

    func clearOperation(token: String) {
        inFlightActions[token] = nil
        operationProgress[token] = nil
        cancellableDownloads.remove(token)
        brewOutputBuffers[token] = nil
        lastProgressUpdates[token] = nil
        runningProcesses[token] = nil
    }

    func consumeBrewOutput(_ output: String, token: String) {
        guard var progress = operationProgress[token],
              progress.phase != .canceling
        else { return }

        let buffered = String(((brewOutputBuffers[token] ?? "") + output).suffix(6_000))
        brewOutputBuffers[token] = buffered

        if let bytes = BrewProgressParser.byteProgress(in: buffered) {
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
        if let phase = BrewProgressParser.latestPhase(in: buffered) {
            progress.phase = phase
            if phase == .performing {
                cancellableDownloads.remove(token)
            }
        }

        operationProgress[token] = progress
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
