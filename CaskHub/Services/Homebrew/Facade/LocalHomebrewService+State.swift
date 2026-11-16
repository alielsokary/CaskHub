//
//  LocalHomebrewService+State.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Foundation

extension LocalHomebrewService {
    func clearError(for token: String) {
        operationStore.send(.clear, for: token)
    }

    func isInstalled(token reference: String) -> Bool {
        makeLocalStateResolver().isInstalled(token: reference)
    }

    func localState(for cask: Cask) -> CaskLocalState {
        makeLocalStateResolver().localState(for: cask)
    }

    /// A value copy of the current inputs, safe to resolve the whole catalog off the main actor.
    func localStateResolver() -> CaskLocalStateResolver {
        makeLocalStateResolver()
    }

    func open(_ cask: Cask) {
        clearError(for: cask.reference)
        openApplication(
            at: makeLocalStateResolver().launchURL(for: cask),
            token: cask.reference
        )
    }

    func openExternalApp(cask: Cask) {
        clearError(for: cask.reference)
        openApplication(
            at: makeLocalStateResolver().externalLaunchURL(for: cask),
            token: cask.reference
        )
    }

    func externalAppVersion(for cask: Cask) -> String? {
        makeLocalStateResolver().externalAppVersion(for: cask)
    }

    func installationDates(for cask: Cask) -> CaskInstallationDates? {
        makeLocalStateResolver().installationDates(for: cask)
    }

    func existingBundleURL(named names: [String]) -> URL? {
        makeLocalStateResolver().existingBundleURL(named: names)
    }

    func hasUnverifiedAppDestination(for cask: Cask) -> Bool {
        let owner = installationSnapshot.externalApplicationOwners[cask.token]
            ?? installationSnapshot.installationIndex.homebrewApplications[cask.token]
        return ApplicationDiscovery().hasOtherBundle(
            named: cask.appArtifactNames, than: owner?.url,
            directories: applicationDirectories, fileManager: fileManager
        )
    }

    private func makeLocalStateResolver() -> CaskLocalStateResolver {
        CaskLocalStateResolver(
            snapshot: installationSnapshot,
            hasRegisteredApplicationCatalog: !applicationCaskSignatures.isEmpty,
            greedyUpdates: greedyUpdates,
            homebrewOutdated: homebrewOutdated,
            platform: caskPlatform,
            applicationDirectories: applicationDirectories,
            fileManager: fileManager
        )
    }

    private func openApplication(at url: URL?, token: String) {
        guard let url else {
            let error = LocalHomebrewError.appBundleNotFound(token: token)
            noteFailure(token: token, error: error)
            Analytics.caskActionFailed(
                .opening,
                token: token,
                failureKind: error.failureKind
            )
            CrashReporter.capture(error, tags: [
                "brew.action": CaskAction.opening.identifier,
                "brew.cask": CaskReference.analyticsName(token),
                "brew.origin": CaskActionOrigin.individual.rawValue
            ])
            return
        }
        applicationLauncher.open(url)
    }
}
