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
        environmentOverrides: [String: String] = [:],
        recoverIf: (() -> Bool)? = nil
    ) async throws {
        try await mutationCoordinator.run(
            HomebrewMutationRequest(
                action: action,
                token: token,
                displayName: displayName(for: token),
                arguments: args,
                origin: origin,
                environmentOverrides: environmentOverrides
            ),
            callbacks: HomebrewMutationCallbacks(
                refresh: { [self] in await refresh() },
                strandedCopyExists: { [self] in hasStrandedCopy(token: token) },
                recoverIf: recoverIf
            )
        )
    }

    func runMutationSequence(
        _ action: CaskAction,
        token: String,
        steps: [HomebrewMutationStep],
        origin: CaskActionOrigin,
        displayName: String? = nil
    ) async throws {
        try await mutationCoordinator.runSequence(
            HomebrewMutationSequenceRequest(
                action: action,
                token: token,
                displayName: displayName ?? self.displayName(for: token),
                origin: origin,
                steps: steps
            ),
            callbacks: HomebrewMutationCallbacks(
                refresh: { [self] in
                    if action == .updatingHomebrew { invalidateBrewVersion() }
                    await refresh()
                },
                strandedCopyExists: { [self] in hasStrandedCopy(token: token) },
                recoverIf: nil
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
}
