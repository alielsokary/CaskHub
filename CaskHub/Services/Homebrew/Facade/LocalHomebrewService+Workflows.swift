//
//  LocalHomebrewService+Workflows.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

extension LocalHomebrewService {
    func install(_ cask: Cask) async throws {
        if let conflict = cask.conflictsWith?.caskTokens.first(where: {
            installedCasks[$0] != nil
        }) {
            Analytics.caskActionFailed(
                .installing,
                token: cask.token,
                failureKind: .caskConflict
            )
            operationStore.send(
                .fail(CaskOperationFailure(
                    kind: .installationPreflight,
                    message: LocalHomebrewError.caskConflictDescription(
                        requestedCask: cask.token,
                        installedCask: conflict
                    )
                )),
                for: cask.token
            )
            return
        }
        try await install(token: cask.token, brewToken: cask.brewToken)
    }

    func install(token: String, brewToken: String? = nil) async throws {
        let commandToken = brewToken ?? token
        try await runMutationSequence(
            .installing,
            token: token,
            steps: [
                .fetch(token: commandToken, cancellation: .untilPerforming),
                .exclusive(["install", "--cask", commandToken], cancellation: .untilPerforming)
            ],
            origin: .individual
        )
    }

    func uninstall(token: String) async throws {
        try await runMutation(
            .uninstalling,
            token: token,
            args: uninstallArguments(token: token),
            origin: .individual
        )
    }

    func uninstallArguments(token: String) -> [String] {
        // Brew rejects plain uninstall for caskfile-less zombies; --force works.
        let force = installedCasks[token]?.isZombie == true
        return ["uninstall", "--cask", token]
            + (force ? ["--force"] : [])
            + (zapOnUninstall ? ["--zap"] : [])
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
        try await stagedReplacement(
            token: token,
            action: .repairing,
            origin: .repair
        )
    }

    /// Homebrew's troubleshooting checklist calls for two update passes: the
    /// first can update brew itself while leaving the original command behind.
    func updateHomebrew(for token: String) async throws {
        let updateStep = HomebrewMutationStep(
            arguments: ["update"],
            environmentOverrides: [:],
            lane: .exclusive,
            cancellation: .never,
            recoverIf: nil,
            recoveryBehavior: .continueSequence
        )
        try await runMutationSequence(
            .updatingHomebrew,
            token: token,
            steps: [updateStep, updateStep],
            origin: .repair,
            displayName: String(localized: "Homebrew")
        )
    }

    /// Package artifacts cannot be adopted as metadata. For a downgrade (or a
    /// recovery after a vendor installer refuses an in-place install), fetch the
    /// payload first, ask Homebrew to run the cask's uninstall stanza even though
    /// it has no receipt (`--force`), then install the requested package.
    func replacePackageForAdoption(
        token: String,
        context: HomebrewMutationContext = .none
    ) async throws {
        try await stagedReplacement(
            token: token,
            action: .adopting,
            origin: .individual,
            context: context
        )
    }

    private func stagedReplacement(
        token: String,
        action: CaskAction,
        origin: CaskActionOrigin,
        context: HomebrewMutationContext = .none
    ) async throws {
        let caskroomEntry = HomebrewLocator.caskroomURL(
            customPrefix: customBrewPrefix,
            fileManager: fileManager
        )?
            .appendingPathComponent(token)
        let appBundleNames = installedCasks[token]?.appBundleNames
            ?? installationSnapshot.externalPackageInstallations[token]?.appBundleNames
            ?? []
        try await runMutationSequence(
            action,
            token: token,
            steps: [
                .fetch(token: token, cancellation: .never),
                HomebrewMutationStep(
                    arguments: ["uninstall", "--cask", token, "--force"],
                    environmentOverrides: ["HOMEBREW_NO_AUTOREMOVE": "1"],
                    lane: .exclusive,
                    cancellation: .never,
                    recoverIf: { [self] in
                        mutationCoordinator.removalSatisfied(
                            caskroomEntry: caskroomEntry,
                            appBundleNames: appBundleNames,
                            applicationDirectories: applicationDirectories
                        )
                    },
                    recoveryBehavior: .continueSequence
                ),
                .exclusive(["install", "--cask", token], cancellation: .never)
            ],
            origin: origin,
            context: context
        )
    }

    func upgrade(
        token: String,
        origin: CaskActionOrigin = .individual
    ) async throws {
        let args = ["upgrade", "--cask", token]
            + (greedyUpdates ? ["--greedy"] : [])
        try await runMutationSequence(
            .updating,
            token: token,
            steps: [
                .fetch(token: token, cancellation: .untilPerforming),
                .exclusive(args, cancellation: .whileQueued)
            ],
            origin: origin
        )
    }

    func updateAll(tokens: [String]) async {
        guard operationStore.beginUpdateAll() else { return }
        defer { operationStore.finishUpdateAll() }
        for token in tokens where operationStore.canBeginOperation(
            .updating,
            for: token
        ) {
            operationStore.send(.enqueue(.updating), for: token)
        }
        _ = await runBatch(tokens, onFinished: { _ in }, operation: { try await self.upgrade(token: $0, origin: .updateAll) })
    }

    /// Returns how many installs failed.
    func installAll(tokens: [String], onFinished: (Int) -> Void) async -> Int {
        await runBatch(tokens, onFinished: onFinished) { try await self.install(token: $0) }
    }

    private func runBatch(
        _ tokens: [String],
        onFinished: (Int) -> Void,
        operation: @escaping @MainActor (String) async throws -> Void
    ) async -> Int {
        let reportsProgress = operationStore.beginBatch(tokens: Set(tokens))
        defer { if reportsProgress { operationStore.endBatch() } }
        return await withTaskGroup(of: Bool.self) { group in
            for token in tokens {
                group.addTask { await (try? operation(token)) != nil }
            }
            var finishedCount = 0
            var failedCount = 0
            for await succeeded in group {
                finishedCount += 1
                if !succeeded { failedCount += 1 }
                if reportsProgress { operationStore.advanceBatch() }
                onFinished(finishedCount)
            }
            return failedCount
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

}
