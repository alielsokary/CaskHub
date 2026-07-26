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
