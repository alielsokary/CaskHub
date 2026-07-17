//
//  LocalHomebrewService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/04/2026.
//

import AppKit
import Foundation
import Observation

// MARK: - Public Types

struct LocalCaskInstallation: Hashable, Identifiable {
    let token: String
    let installedVersion: String
    let installedAt: Date?
    let appBundleNames: [String]

    var id: String {
        token
    }
}

enum CaskAction: Equatable {
    case opening
    case installing
    case updating
    case uninstalling
    case queued

    var inProgressLabel: String {
        switch self {
        case .opening: return "Opening…"
        case .installing: return "Installing…"
        case .updating: return "Updating…"
        case .uninstalling: return "Uninstalling…"
        case .queued: return "Queued…"
        }
    }
}

enum LocalHomebrewError: LocalizedError {
    case brewBinaryNotFound
    case caskroomNotFound
    case appBundleNotFound(token: String)
    case brewCommandFailed(args: [String], exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .brewBinaryNotFound:
            return "Couldn't locate the brew binary. Is Homebrew installed?"
        case .caskroomNotFound:
            return "Couldn't locate the Homebrew Caskroom."
        case let .appBundleNotFound(token):
            return "Couldn't find an installed app for \(token)."
        case let .brewCommandFailed(args, code, stderr):
            let cmd = (["brew"] + args).joined(separator: " ")
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("reports different checksum") || trimmed.contains("SHA256 mismatch") {
                return "The download doesn't match the checksum Homebrew has on record — "
                    + "the developer likely replaced the release file after it was published. "
                    + "This isn't a problem with your Mac; Homebrew refuses mismatched downloads "
                    + "for security. Try again in a day or two once the cask is updated."
            }
            return trimmed.isEmpty
                ? "`\(cmd)` failed (exit \(code))."
                : "`\(cmd)` failed (exit \(code)): \(trimmed)"
        }
    }
}

// MARK: - LocalHomebrewService

@MainActor
@Observable
final class LocalHomebrewService {
    var installedCasks: [String: LocalCaskInstallation] = [:]

    private(set) var inFlightActions: [String: CaskAction] = [:]

    private(set) var cancellableDownloads: Set<String> = []

    private(set) var cancelRequested: Set<String> = []

    @ObservationIgnored private var runningProcesses: [String: Process] = [:]

    private(set) var actionErrors: [String: String] = [:]

    private(set) var isUpdatingAll = false

    private(set) var lastRefresh: Date?

    private(set) var refreshError: LocalHomebrewError?

    private(set) var brewVersion: String?

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Detection

    func refresh() async {
        let fm = fileManager
        if brewVersion == nil {
            brewVersion = await Self.fetchBrewVersion()
        }
        let result = await Task.detached(priority: .userInitiated) {
            Self.scanCaskroom(fileManager: fm)
        }.value

        switch result {
        case let .success(casks):
            installedCasks = casks
            refreshError = nil
        case let .failure(error):
            refreshError = error
            CrashReporter.capture(error)
        }
        lastRefresh = .now
    }

    func isInstalled(token: String) -> Bool {
        installedCasks[token] != nil
    }

    func clearError(for token: String) {
        actionErrors[token] = nil
    }

    func isOutdated(token: String, remoteVersion: String) -> Bool {
        guard let installation = installedCasks[token] else { return false }
        return Self.comparableVersion(installation.installedVersion)
            != Self.comparableVersion(remoteVersion)
    }

    private nonisolated static func comparableVersion(_ version: String) -> Substring {
        version.prefix { $0 != "," && $0 != "_" }
    }

    func hasAvailableUpdate(token: String, remoteVersion: String, autoUpdates: Bool?) -> Bool {
        autoUpdates != true && isOutdated(token: token, remoteVersion: remoteVersion)
    }

    // MARK: - Actions

    func openApp(token: String) {
        actionErrors[token] = nil

        guard let installation = installedCasks[token] else {
            actionErrors[token] = LocalHomebrewError.appBundleNotFound(token: token).errorDescription
            return
        }

        let candidates = installation.appBundleNames.flatMap { name -> [URL] in
            [
                URL(fileURLWithPath: "/Applications").appendingPathComponent(name),
                fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent("Applications")
                    .appendingPathComponent(name)
            ]
        }

        guard let appURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            actionErrors[token] = LocalHomebrewError.appBundleNotFound(token: token).errorDescription
            return
        }

        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    func install(token: String) async throws {
        try await runMutation(.installing, token: token, args: ["install", "--cask", token])
    }

    func uninstall(token: String) async throws {
        try await runMutation(.uninstalling, token: token, args: ["uninstall", "--cask", token])
    }

    func upgrade(token: String) async throws {
        try await runMutation(.updating, token: token, args: ["upgrade", "--cask", token])
    }

    func updateAll(tokens: [String]) async {
        guard !isUpdatingAll else { return }
        isUpdatingAll = true
        defer { isUpdatingAll = false }
        for token in tokens where inFlightActions[token] == nil {
            inFlightActions[token] = .queued
        }
        for token in tokens {
            try? await upgrade(token: token)
        }
    }

    func cancelInstall(token: String) {
        guard cancellableDownloads.contains(token),
              let process = runningProcesses[token] else { return }
        cancelRequested.insert(token)
        cancellableDownloads.remove(token)

        let pid = process.processIdentifier
        Task.detached(priority: .userInitiated) {
            Self.signalTree(pid: pid, signal: SIGINT)
            try? await Task.sleep(for: .seconds(5))
            if process.isRunning { process.terminate() }
        }
    }

    // MARK: - Mutation Plumbing

    private func runMutation(_ action: CaskAction, token: String, args: [String]) async throws {
        guard inFlightActions[token] == nil || inFlightActions[token] == .queued else { return }
        inFlightActions[token] = action
        actionErrors[token] = nil
        let startedAt = Date.now
        defer {
            inFlightActions[token] = nil
            cancellableDownloads.remove(token)
            runningProcesses[token] = nil
        }

        let span = CrashReporter.span(name: args.first ?? "brew", operation: "brew")
        do {
            try await runBrewStreaming(token: token, args: args, cancellable: action == .installing)
            span.finish()
            cancelRequested.remove(token)
            Analytics.caskActionCompleted(action, token: token)
            await refresh()
        } catch {
            if cancelRequested.contains(token) {
                span.finish()
                cancelRequested.remove(token)
                Task.detached(priority: .utility) {
                    Self.cleanupIncompleteDownloads(since: startedAt)
                }
                await refresh()
                return
            }
            span.finish(error: error)
            CrashReporter.capture(error)
            Analytics.caskActionFailed(action, token: token)
            if let error = error as? LocalHomebrewError {
                actionErrors[token] = error.errorDescription
            } else {
                actionErrors[token] = error.localizedDescription
            }
            throw error
        }
    }

    private func runBrewStreaming(token: String, args: [String], cancellable: Bool) async throws {
        guard let brewURL = Self.locateBrewBinary() else {
            throw LocalHomebrewError.brewBinaryNotFound
        }

        let process = Process()
        process.executableURL = brewURL
        process.arguments = args
        if let askpass = Self.ensureAskpassScript(token: token) {
            var environment = ProcessInfo.processInfo.environment
            environment["SUDO_ASKPASS"] = askpass.path
            process.environment = environment
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        runningProcesses[token] = process
        if cancellable { cancellableDownloads.insert(token) }

        let handle = pipe.fileHandleForReading
        let outputTail = await Task.detached(priority: .userInitiated) { () -> String in
            var tail = ""
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { break }
                guard let text = String(data: data, encoding: .utf8) else { continue }
                tail = String((tail + text).suffix(2000))

                if text.contains("==> Installing Cask") {
                    Task { @MainActor in self.cancellableDownloads.remove(token) }
                }
            }
            process.waitUntilExit()
            return tail
        }.value

        if process.terminationStatus != 0 {
            throw LocalHomebrewError.brewCommandFailed(
                args: args,
                exitCode: process.terminationStatus,
                stderr: outputTail.components(separatedBy: "\n").suffix(6).joined(separator: "\n")
            )
        }
    }
}
