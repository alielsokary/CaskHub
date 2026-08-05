//
//  LocalHomebrewService+Workflows.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

extension LocalHomebrewService {
    func install(token: String) async throws {
        try await runMutation(
            .installing,
            token: token,
            args: ["install", "--cask", token],
            origin: .individual
        )
    }

    func uninstall(token: String) async throws {
        // Zombie entries lack brew's timestamped caskfile, so plain uninstall
        // is rejected with "Cask 'x' is not installed"; --force still works.
        let force = installedCasks[token]?.isZombie == true
        try await runMutation(
            .uninstalling,
            token: token,
            args: ["uninstall", "--cask", token] + (force ? ["--force"] : []),
            origin: .individual
        )
    }

    /// Clears a zombie Caskroom entry — the app is already gone, `--force`
    /// removes the leftover brew bookkeeping without complaining about it.
    func repair(token: String) async throws {
        try await runMutation(
            .uninstalling,
            token: token,
            args: ["uninstall", "--cask", token, "--force"],
            origin: .repair
        )
    }

    /// A stranded copy inside the Caskroom wedges every upgrade: clear brew's
    /// records (`--force` tolerates the mess), then install fresh. Settings
    /// and user data live outside the bundle and survive.
    /// The download comes FIRST: a failed fetch after the uninstall would
    /// leave the user with no app at all, and `brew fetch` exits non-zero on
    /// download failure, so it's a reliable gate.
    func repairReinstalling(token: String) async throws {
        guard operationStore.canBeginOperation(for: token) else { return }
        let caskroomEntry = HomebrewLocator.caskroomURL(
            customPrefix: customBrewPrefix,
            fileManager: fileManager
        )?
            .appendingPathComponent(token)
        let appBundleNames = installedCasks[token]?.appBundleNames ?? []
        Analytics.caskActionStarted(.repairing, token: token, origin: .repair)
        try await prepareRepairDownload(token: token)
        do {
            try await runMutation(
                .uninstalling,
                token: token,
                args: ["uninstall", "--cask", token, "--force"],
                origin: .repair,
                environmentOverrides: ["HOMEBREW_NO_AUTOREMOVE": "1"],
                recoverIf: { [self] in
                    mutationCoordinator.removalSatisfied(
                        caskroomEntry: caskroomEntry,
                        appBundleNames: appBundleNames,
                        applicationDirectories: applicationDirectories
                    )
                }
            )
            try await runMutation(
                .installing,
                token: token,
                args: ["install", "--cask", token],
                origin: .repair
            )
            Analytics.caskActionCompleted(
                .repairing,
                token: token,
                origin: .repair
            )
        } catch {
            Analytics.caskActionFailed(
                .repairing,
                token: token,
                origin: .repair
            )
            throw error
        }
    }

    func upgrade(
        token: String,
        origin: CaskActionOrigin = .individual
    ) async throws {
        let args = ["upgrade", "--cask", token]
            + (greedyUpdates ? ["--greedy"] : [])
        try await runMutation(
            .updating,
            token: token,
            args: args,
            origin: origin
        )
    }

    func updateAll(tokens: [String]) async {
        guard operationStore.beginUpdateAll() else { return }
        defer { operationStore.finishUpdateAll() }
        for token in tokens where operationStore.canBeginOperation(for: token) {
            operationStore.send(.enqueue(.updating), for: token)
        }
        for (index, token) in tokens.enumerated() {
            operationStore.setUpdateAllProgress(CaskUpdateAllProgress(
                currentIndex: index + 1,
                totalCount: tokens.count,
                currentToken: token,
                currentDisplayName: displayName(for: token)
            ))
            try? await upgrade(token: token, origin: .updateAll)
        }
    }

    func cancelInstall(token: String) {
        mutationCoordinator.cancel(token: token)
    }

    var statusBarOperation: CaskOperationStatus? {
        operationStore.status
    }

    func displayName(for token: String) -> String {
        caskDisplayNames[token] ?? token
    }

    private func prepareRepairDownload(token: String) async throws {
        mutationCoordinator.beginOperation(
            .repairing,
            token: token,
            displayName: displayName(for: token)
        )
        defer { mutationCoordinator.clearOperationResources(token: token) }
        do {
            try await mutationCoordinator.executeStreaming(
                token: token,
                arguments: ["fetch", "--cask", token],
                cancellable: false
            )
            operationStore.send(.clear, for: token)
        } catch {
            CrashReporter.capture(error)
            Analytics.caskActionFailed(
                .repairing,
                token: token,
                origin: .repair
            )
            noteFailure(token: token, error: error)
            throw error
        }
    }
}
