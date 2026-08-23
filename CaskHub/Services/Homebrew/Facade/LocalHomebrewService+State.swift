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

    func isInstalled(token: String) -> Bool {
        makeLocalStateResolver().isInstalled(token: token)
    }

    func localState(for cask: Cask) -> CaskLocalState {
        makeLocalStateResolver().localState(for: cask)
    }

    func localStates(for casks: [Cask]) -> [String: CaskLocalState] {
        let resolver = makeLocalStateResolver()
        return casks.reduce(into: [:]) { result, cask in
            result[cask.token] = resolver.localState(for: cask)
        }
    }

    func open(_ cask: Cask) {
        clearError(for: cask.token)
        openApplication(
            at: makeLocalStateResolver().launchURL(for: cask),
            token: cask.token
        )
    }

    func openExternalApp(cask: Cask) {
        clearError(for: cask.token)
        openApplication(
            at: makeLocalStateResolver().externalLaunchURL(for: cask),
            token: cask.token
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

    private func makeLocalStateResolver() -> CaskLocalStateResolver {
        CaskLocalStateResolver(
            snapshot: installationSnapshot,
            hasRegisteredApplicationCatalog: !applicationCaskSignatures.isEmpty,
            greedyUpdates: greedyUpdates,
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
                "brew.cask": token,
                "brew.origin": CaskActionOrigin.individual.rawValue
            ])
            return
        }
        applicationLauncher.open(url)
    }
}
