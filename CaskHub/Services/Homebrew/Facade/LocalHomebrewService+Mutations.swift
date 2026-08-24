//
//  LocalHomebrewService+Mutations.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Foundation

extension LocalHomebrewService {
    func noteFailure(token: String, error: Error) {
        mutationCoordinator.recordFailure(
            token: token,
            error: error,
            strandedCopyExists: hasStrandedCopy(token: token)
        )
    }

    func runMutation(
        _ action: CaskAction,
        token: String,
        args: [String],
        origin: CaskActionOrigin = .individual,
        context: HomebrewMutationContext = .none
    ) async throws {
        let previousInstallation = installationSnapshot.installedCasks[token]
        try await mutationCoordinator.runSequence(
            HomebrewMutationSequenceRequest(
                action: action,
                token: token,
                displayName: displayName(for: token),
                origin: origin,
                steps: [
                    HomebrewMutationStep(
                        arguments: args,
                        environmentOverrides: [:],
                        cancellable: action == .installing,
                        recoverIf: nil,
                        recoveryBehavior: .finishMutation
                    )
                ],
                context: context
            ),
            callbacks: HomebrewMutationCallbacks(
                refresh: { [self] in await refresh() },
                strandedCopyExists: { [self] in hasStrandedCopy(token: token) },
                postconditionSatisfied: { [self] in
                    mutationPostconditionSatisfied(
                        action: action,
                        token: token,
                        previousInstallation: previousInstallation
                    )
                }
            )
        )
    }

    func runMutationSequence(
        _ action: CaskAction,
        token: String,
        steps: [HomebrewMutationStep],
        origin: CaskActionOrigin,
        displayName: String? = nil,
        context: HomebrewMutationContext = .none
    ) async throws {
        let previousInstallation = installationSnapshot.installedCasks[token]
        try await mutationCoordinator.runSequence(
            HomebrewMutationSequenceRequest(
                action: action,
                token: token,
                displayName: displayName ?? self.displayName(for: token),
                origin: origin,
                steps: steps,
                context: context
            ),
            callbacks: HomebrewMutationCallbacks(
                refresh: { [self] in
                    if action == .updatingHomebrew { invalidateBrewVersion() }
                    await refresh()
                },
                strandedCopyExists: { [self] in hasStrandedCopy(token: token) },
                postconditionSatisfied: { [self] in
                    mutationPostconditionSatisfied(
                        action: action,
                        token: token,
                        previousInstallation: previousInstallation
                    )
                }
            )
        )
    }

    private func hasStrandedCopy(token: String) -> Bool {
        guard let caskroom = HomebrewLocator.caskroomURL(
            customPrefix: customBrewPrefix,
            fileManager: fileManager
        ) else { return false }
        return HomebrewInstallationScanner.strandedCopyExists(
            in: caskroom,
            token: token,
            fileManager: fileManager
        )
    }

    private func mutationPostconditionSatisfied(
        action: CaskAction,
        token: String,
        previousInstallation: LocalCaskInstallation?
    ) -> Bool {
        let current = installationSnapshot.installedCasks[token]
        switch action {
        case .installing, .adopting, .repairing:
            return current?.isZombie == false
        case .uninstalling:
            return current == nil
        case .updating:
            return current?.isZombie == false && current != previousInstallation
        case .opening, .updatingHomebrew, .queued:
            return false
        }
    }
}
