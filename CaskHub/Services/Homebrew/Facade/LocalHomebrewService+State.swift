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

    func isPresent(_ cask: Cask) -> Bool {
        makeLocalStateResolver().isPresent(cask)
    }

    func isAdoptable(_ cask: Cask) -> Bool {
        makeLocalStateResolver().isAdoptable(cask)
    }

    func isAdoptableApplication(_ cask: Cask) -> Bool {
        makeLocalStateResolver().isAdoptableApplication(cask)
    }

    func isExternalPackageInstalled(_ cask: Cask) -> Bool {
        makeLocalStateResolver().isExternalPackageInstalled(cask)
    }

    func isMacAppStoreInstalled(_ cask: Cask) -> Bool {
        makeLocalStateResolver().isMacAppStoreInstalled(cask)
    }

    func externalCLIPath(_ cask: Cask) -> URL? {
        makeLocalStateResolver().externalCLIPath(cask)
    }

    func installationSource(for cask: Cask) -> CaskInstallationSource? {
        makeLocalStateResolver().installationSource(for: cask)
    }

    func uninstallAvailability(for cask: Cask) -> CaskUninstallAvailability {
        makeLocalStateResolver().uninstallAvailability(for: cask)
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

    func isOutdated(token: String, remoteVersion: String) -> Bool {
        makeLocalStateResolver().isOutdated(
            token: token,
            remoteVersion: remoteVersion
        )
    }

    func hasAvailableUpdate(
        token: String,
        remoteVersion: String,
        autoUpdates: Bool?
    ) -> Bool {
        makeLocalStateResolver().hasAvailableUpdate(
            token: token,
            remoteVersion: remoteVersion,
            autoUpdates: autoUpdates
        )
    }

    func isZombie(_ cask: Cask) -> Bool {
        makeLocalStateResolver().isZombie(cask)
    }

    func canOpen(_ cask: Cask) -> Bool {
        makeLocalStateResolver().canOpen(cask)
    }

    func open(_ cask: Cask) {
        clearError(for: cask.token)
        openApplication(
            at: makeLocalStateResolver().launchURL(for: cask),
            token: cask.token
        )
    }

    func openApp(token: String) {
        clearError(for: token)
        openApplication(
            at: makeLocalStateResolver().launchURL(forInstalledToken: token),
            token: token
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
            noteFailure(
                token: token,
                error: LocalHomebrewError.appBundleNotFound(token: token)
            )
            return
        }
        applicationLauncher.open(url)
    }
}
