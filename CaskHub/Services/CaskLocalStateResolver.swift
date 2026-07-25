//
//  CaskLocalStateResolver.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

struct CaskLocalStateResolver {
    let snapshot: InstallationSnapshot
    let hasRegisteredApplicationCatalog: Bool
    let greedyUpdates: Bool
    let applicationDirectories: [URL]
    let fileManager: FileManager

    private let applicationDiscovery = ApplicationDiscovery()

    func isInstalled(token: String) -> Bool {
        snapshot.installedCasks[token] != nil
    }

    func isPresent(_ cask: Cask) -> Bool {
        isInstalled(token: cask.token)
            || isMacAppStoreInstalled(cask)
            || isAdoptable(cask)
            || externalCLIPath(cask) != nil
    }

    func isAdoptable(_ cask: Cask) -> Bool {
        isAdoptableApplication(cask) || isExternalPackageInstalled(cask)
    }

    func isAdoptableApplication(_ cask: Cask) -> Bool {
        guard !isInstalled(token: cask.token) else { return false }
        if hasRegisteredApplicationCatalog {
            return snapshot.externalApplicationOwners[cask.token] != nil
        }
        return cask.appArtifactNames.contains(
            where: snapshot.externalAppNames.contains
        )
    }

    func isExternalPackageInstalled(_ cask: Cask) -> Bool {
        !isInstalled(token: cask.token)
            && snapshot.externalPackageInstallations[cask.token] != nil
    }

    func isMacAppStoreInstalled(_ cask: Cask) -> Bool {
        guard !isInstalled(token: cask.token) else { return false }
        if snapshot.installationIndex.catalogTokens.contains(cask.token) {
            return snapshot.installationIndex.macAppStoreApplications[cask.token] != nil
        }
        if macAppStoreApplication(for: cask) != nil { return true }

        let matchingNames = Set(
            cask.appArtifactNames + cask.packageAppNameCandidates
        )
        .intersection(snapshot.macAppStoreAppNames)
        guard !matchingNames.isEmpty else { return false }

        guard cask.hasPackageArtifact else { return true }
        return matchingNames.contains { appName in
            snapshot.macAppStoreBundleIdentifiers[appName]?.contains {
                storeBundleIdentifier($0, matches: cask)
            } == true
        }
    }

    func externalCLIPath(_ cask: Cask) -> URL? {
        guard !isInstalled(token: cask.token) else { return nil }
        if snapshot.installationIndex.catalogTokens.contains(cask.token) {
            return snapshot.installationIndex.externalCLIPaths[cask.token]
        }
        return cask.binaryArtifactNames.lazy.compactMap {
            snapshot.externalBinaryPaths[$0]
        }
        .first
    }

    func installationSource(for cask: Cask) -> CaskInstallationSource? {
        if isInstalled(token: cask.token) { return .homebrew }
        if isMacAppStoreInstalled(cask) { return .macAppStore }
        if isExternalPackageInstalled(cask) { return .packageInstaller }
        if isAdoptableApplication(cask) { return .externalApplication }
        if externalCLIPath(cask) != nil { return .externalExecutable }
        return nil
    }

    func uninstallAvailability(for cask: Cask) -> CaskUninstallAvailability {
        if isInstalled(token: cask.token) {
            return .available
        }
        if isAdoptable(cask) {
            return .unavailable(
                reason: "Adopt this app first so CaskHub can manage/uninstall it."
            )
        }
        if isMacAppStoreInstalled(cask) {
            return .unavailable(
                reason: "Installed from the Mac App Store. "
                    + "Uninstall it from Finder or Launchpad."
            )
        }
        if let externalPath = externalCLIPath(cask) {
            return .unavailable(
                reason: "Installed outside Homebrew at \(externalPath.path). "
                    + "Remove or move that file manually before installing "
                    + "the Homebrew version."
            )
        }
        return .notApplicable
    }

    func localState(for cask: Cask) -> CaskLocalState {
        let source = installationSource(for: cask)
        return CaskLocalState(
            installationSource: source,
            externalCLIPath: source == .externalExecutable
                ? externalCLIPath(cask)
                : nil,
            uninstallAvailability: uninstallAvailability(for: cask),
            hasAvailableUpdate: hasAvailableUpdate(
                token: cask.token,
                remoteVersion: cask.version,
                autoUpdates: cask.autoUpdates
            ),
            isZombie: isZombie(cask),
            canOpen: canOpen(cask)
        )
    }

    func isOutdated(token: String, remoteVersion: String) -> Bool {
        guard let installation = snapshot.installedCasks[token],
              !installation.isZombie
        else { return false }
        return Self.comparableVersion(installation.installedVersion)
            != Self.comparableVersion(remoteVersion)
    }

    func hasAvailableUpdate(
        token: String,
        remoteVersion: String,
        autoUpdates: Bool?
    ) -> Bool {
        (greedyUpdates || autoUpdates != true)
            && isOutdated(token: token, remoteVersion: remoteVersion)
    }

    func isZombie(_ cask: Cask) -> Bool {
        guard let installation = snapshot.installedCasks[cask.token],
              installation.isZombie,
              !cask.appArtifactNames.isEmpty
        else { return false }
        if snapshot.installationIndex.catalogTokens.contains(cask.token) {
            return snapshot.installationIndex.verifiedZombieTokens.contains(
                cask.token
            )
        }
        return existingBundleURL(named: cask.appArtifactNames) == nil
    }

    func canOpen(_ cask: Cask) -> Bool {
        if snapshot.installationIndex.catalogTokens.contains(cask.token) {
            if isInstalled(token: cask.token) {
                return snapshot.installationIndex.launchableHomebrewTokens.contains(
                    cask.token
                )
            }
            return snapshot.installationIndex
                .macAppStoreApplications[cask.token] != nil
                || snapshot.externalApplicationOwners[cask.token] != nil
                || snapshot.externalPackageInstallations[cask.token] != nil
        }
        if !isInstalled(token: cask.token),
           let application = macAppStoreApplication(for: cask) {
            return applicationDiscovery.metadata(
                at: application.url,
                fileManager: fileManager
            ) != nil
        }
        return launchURL(for: cask) != nil
    }

    func launchURL(for cask: Cask) -> URL? {
        existingBundleURL(named: launchableBundleNames(for: cask))
    }

    func launchURL(forInstalledToken token: String) -> URL? {
        guard let installation = snapshot.installedCasks[token] else {
            return nil
        }
        return existingBundleURL(named: installation.appBundleNames)
    }

    func externalLaunchURL(for cask: Cask) -> URL? {
        macAppStoreApplication(for: cask)?.url
            ?? snapshot.externalApplicationOwners[cask.token]?.url
            ?? existingBundleURL(named: externalBundleNameCandidates(for: cask))
    }

    func externalAppVersion(for cask: Cask) -> String? {
        guard !isInstalled(token: cask.token),
              installationSource(for: cask) != nil,
              let appURL = externalLaunchURL(for: cask),
              let info = Bundle(url: appURL)?.infoDictionary
        else { return nil }
        return info["CFBundleShortVersionString"] as? String
            ?? info["CFBundleVersion"] as? String
    }

    func existingBundleURL(named names: [String]) -> URL? {
        let nameSet = Set(names)
        if let detected = snapshot.detectedApplications.first(where: {
            nameSet.contains($0.bundleName)
                && applicationDiscovery.metadata(
                    at: $0.url,
                    fileManager: fileManager
                ) != nil
        }) {
            return detected.url
        }

        return names.flatMap { name in
            applicationDirectories.map { $0.appendingPathComponent(name) }
        }
        .first {
            applicationDiscovery.metadata(at: $0, fileManager: fileManager) != nil
        }
    }

    private static func comparableVersion(_ version: String) -> Substring {
        version.prefix { $0 != "," && $0 != "_" }
    }

    private func launchableBundleNames(for cask: Cask) -> [String] {
        let receiptNames = snapshot.installedCasks[cask.token]?.appBundleNames ?? []
        return receiptNames + externalBundleNameCandidates(for: cask)
    }

    private func externalBundleNameCandidates(for cask: Cask) -> [String] {
        let packageNames =
            snapshot.externalPackageInstallations[cask.token]?.appBundleNames
            ?? []
        return packageNames
            + cask.appArtifactNames
            + cask.packageAppNameCandidates
    }

    private func macAppStoreApplication(for cask: Cask) -> DetectedApplication? {
        if snapshot.installationIndex.catalogTokens.contains(cask.token) {
            return snapshot.installationIndex.macAppStoreApplications[cask.token]
        }
        let matchingNames = Set(
            cask.appArtifactNames + cask.packageAppNameCandidates
        )
        return snapshot.detectedApplications.first { application in
            guard application.isMacAppStore,
                  matchingNames.contains(application.bundleName)
            else { return false }
            guard cask.hasPackageArtifact else { return true }
            guard let bundleIdentifier = application.bundleIdentifier else {
                return false
            }
            return storeBundleIdentifier(bundleIdentifier, matches: cask)
        }
    }

    private func storeBundleIdentifier(
        _ identifier: String,
        matches cask: Cask
    ) -> Bool {
        if !cask.applicationBundleIdentifiers.isEmpty {
            return ApplicationIdentityMatcher.applicationBundleIdentifier(
                identifier,
                matchesAny: cask.applicationBundleIdentifiers
            )
        }
        return ApplicationIdentityMatcher.bundleIdentifier(
            identifier,
            matchesPackageIdentifiers: cask.packageIdentifiers
        )
    }
}
