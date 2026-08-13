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
        try await install(token: cask.token)
    }

    func install(token: String) async throws {
        try await runMutation(
            .installing,
            token: token,
            args: ["install", "--cask", token],
            origin: .individual
        )
    }

    func uninstall(token: String) async throws {
        // Brew rejects plain uninstall for caskfile-less zombies; --force works.
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
            cancellable: false,
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
    func replacePackageForAdoption(token: String) async throws {
        try await stagedReplacement(
            token: token,
            action: .adopting,
            origin: .individual
        )
    }

    private func stagedReplacement(
        token: String,
        action: CaskAction,
        origin: CaskActionOrigin
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
                HomebrewMutationStep(
                    arguments: ["fetch", "--cask", token],
                    environmentOverrides: [:],
                    cancellable: false,
                    recoverIf: nil,
                    recoveryBehavior: .finishMutation
                ),
                HomebrewMutationStep(
                    arguments: ["uninstall", "--cask", token, "--force"],
                    environmentOverrides: ["HOMEBREW_NO_AUTOREMOVE": "1"],
                    cancellable: false,
                    recoverIf: { [self] in
                        mutationCoordinator.removalSatisfied(
                            caskroomEntry: caskroomEntry,
                            appBundleNames: appBundleNames,
                            applicationDirectories: applicationDirectories
                        )
                    },
                    recoveryBehavior: .continueSequence
                ),
                HomebrewMutationStep(
                    arguments: ["install", "--cask", token],
                    environmentOverrides: [:],
                    cancellable: false,
                    recoverIf: nil,
                    recoveryBehavior: .finishMutation
                )
            ],
            origin: origin
        )
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
        for token in tokens where operationStore.canBeginOperation(
            .updating,
            for: token
        ) {
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

}
