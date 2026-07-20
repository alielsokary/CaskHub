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
        inFlightActions[token] = action
        actionErrors[token] = nil
        Analytics.caskActionStarted(action, token: token, origin: origin)
        defer {
            inFlightActions[token] = nil
            cancellableDownloads.remove(token)
            runningProcesses[token] = nil
        }

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
        guard let caskroom = Self.locateCaskroom(fileManager: fileManager) else { return false }
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

        let result = try await processRunner.run(
            executableURL: brewURL,
            arguments: args,
            environment: environment,
            onStart: { [weak self] process in
                self?.runningProcesses[token] = process
                if cancellable { self?.cancellableDownloads.insert(token) }
            },
            onChunk: { [weak self] text in
                guard text.contains("==> Installing Cask") else { return }
                guard let self else { return }
                Task { @MainActor in self.cancellableDownloads.remove(token) }
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
