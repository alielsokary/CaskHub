//
//  LocalHomebrewService+State.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Foundation

extension LocalHomebrewService {
    func clearError(for token: String) {
        actionErrors[token] = nil
        adoptReplaceOffers.remove(token)
        repairOffers.remove(token)
        appManagementDenials.remove(token)
    }

    func isInstalled(token: String) -> Bool {
        installedCasks[token] != nil
    }

    /// The cask isn't brew-managed, but its app already sits in /Applications.
    func isAdoptable(_ cask: Cask) -> Bool {
        installedCasks[cask.token] == nil
            && cask.appArtifactNames.contains(where: externalAppNames.contains)
    }

    /// Mac App Store apps are present, but adopting them would break Store updates.
    func isMacAppStoreInstalled(_ cask: Cask) -> Bool {
        installedCasks[cask.token] == nil
            && cask.appArtifactNames.contains(where: macAppStoreAppNames.contains)
    }

    /// A CLI cask whose tool is on the device via some other installer
    /// (e.g. claude-code's native install script). Detected, not managed.
    func isExternalCLI(_ cask: Cask) -> Bool {
        installedCasks[cask.token] == nil
            && cask.binaryArtifactNames.contains(where: externalBinaryNames.contains)
    }

    func isOutdated(token: String, remoteVersion: String) -> Bool {
        guard let installation = installedCasks[token], !installation.isZombie else { return false }
        return Self.comparableVersion(installation.installedVersion)
            != Self.comparableVersion(remoteVersion)
    }

    private nonisolated static func comparableVersion(_ version: String) -> Substring {
        version.prefix { $0 != "," && $0 != "_" }
    }

    func hasAvailableUpdate(token: String, remoteVersion: String, autoUpdates: Bool?) -> Bool {
        (greedyUpdates || autoUpdates != true) && isOutdated(token: token, remoteVersion: remoteVersion)
    }

    /// The scan's zombie verdict cross-checked against the *current* cask
    /// artifacts: auto-updating apps can rename their bundle on disk
    /// (Codex.app → ChatGPT.app), stranding the install-time receipt and
    /// symlink while the app lives on under its new name. Deletion is only
    /// offered when the apps the cask declares today are verifiably gone too.
    func isZombie(_ cask: Cask) -> Bool {
        guard let installation = installedCasks[cask.token], installation.isZombie,
              !cask.appArtifactNames.isEmpty
        else { return false }
        return existingBundleURL(named: cask.appArtifactNames) == nil
    }

    /// Opens via the receipt's bundle names, falling back to the cask's current
    /// artifact names — receipts go stale when apps rename themselves.
    func open(_ cask: Cask) {
        actionErrors[cask.token] = nil
        let receiptNames = installedCasks[cask.token]?.appBundleNames ?? []
        openBundle(named: receiptNames + cask.appArtifactNames, token: cask.token)
    }

    func openApp(token: String) {
        actionErrors[token] = nil

        guard let installation = installedCasks[token] else {
            actionErrors[token] = LocalHomebrewError.appBundleNotFound(token: token).errorDescription
            return
        }
        openBundle(named: installation.appBundleNames, token: token)
    }

    /// Launches a not-yet-adopted app straight from its on-disk bundle.
    func openExternalApp(cask: Cask) {
        actionErrors[cask.token] = nil
        openBundle(named: cask.appArtifactNames, token: cask.token)
    }

    /// Version of a not-yet-adopted app, read from its bundle's Info.plist.
    func externalAppVersion(for cask: Cask) -> String? {
        guard installedCasks[cask.token] == nil,
              let appURL = existingBundleURL(named: cask.appArtifactNames),
              let info = Bundle(url: appURL)?.infoDictionary
        else { return nil }
        return info["CFBundleShortVersionString"] as? String
            ?? info["CFBundleVersion"] as? String
    }

    private func openBundle(named names: [String], token: String) {
        guard let appURL = existingBundleURL(named: names) else {
            actionErrors[token] = LocalHomebrewError.appBundleNotFound(token: token).errorDescription
            return
        }
        appLauncher(appURL)
    }

    func existingBundleURL(named names: [String]) -> URL? {
        names.flatMap { name in
            applicationDirectories.map { $0.appendingPathComponent(name) }
        }
        .first { fileManager.fileExists(atPath: $0.path) }
    }
}
