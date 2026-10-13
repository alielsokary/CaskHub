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
        try await runMutationSequence(
            action,
            token: token,
            steps: [.exclusive(args, cancellation: .never)],
            origin: origin,
            context: context
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

    /// An interrupted uninstall leaves the cask's own app inside the Caskroom, which brew then refuses to overwrite.
    func hasStrandedInstalledApp(token: String) -> Bool {
        guard let names = installedCasks[token]?.appBundleNames,
              let caskroom = HomebrewLocator.caskroomURL(
                  customPrefix: customBrewPrefix,
                  fileManager: fileManager
              )
        else { return false }
        return !HomebrewInstallationScanner.strandedCopyNames(
            in: caskroom,
            token: token,
            fileManager: fileManager
        ).isDisjoint(with: names)
    }

    private func mutationPostconditionSatisfied(
        action: CaskAction,
        token: String,
        previousInstallation: LocalCaskInstallation?
    ) -> Bool {
        let current = installationSnapshot.installedCasks[token]
        switch action {
        case .installing, .adopting, .repairing, .updating:
            return current?.isZombie == false && current != previousInstallation
        case .uninstalling:
            return current == nil
        case .opening, .updatingHomebrew, .queued:
            return false
        }
    }
}
