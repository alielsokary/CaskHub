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
    let homebrewOutdated: HomebrewOutdatedReport?
    let platform: CaskPlatform?
    let applicationDirectories: [URL]
    let fileManager: FileManager

    private let applicationDiscovery = ApplicationDiscovery()

    func isInstalled(token: String) -> Bool {
        snapshot.installedCasks[token] != nil
    }

    func isAdoptable(_ cask: Cask) -> Bool {
        isAdoptableApplication(cask) || isExternalPackageInstalled(cask)
    }

    func isAdoptableApplication(_ cask: Cask) -> Bool {
        guard !isInstalled(token: cask.token) else { return false }
        if hasRegisteredApplicationCatalog || snapshot.externalApplicationOwners[cask.token] != nil {
            return snapshot.externalApplicationOwners[cask.token] != nil
        }
        return cask.appArtifactNames.lazy
            .flatMap { snapshot.detectedApplicationsByBundleName[$0] ?? [] }
            .contains { application in
                guard !application.isMacAppStore,
                      application.isDirectlyInApplicationDirectory,
                      let identifier = application.bundleIdentifier else { return false }
                return ApplicationIdentityMatcher.applicationBundleIdentifier(
                    identifier, matchesAny: cask.applicationBundleIdentifiers
                )
            }
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

        let matchingNames = Set(cask.storeAppNames)
        .intersection(snapshot.macAppStoreAppNames)
        guard !matchingNames.isEmpty else { return false }

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
        if isAdoptableApplication(cask) { return .externalApplication }
        if isExternalPackageInstalled(cask) { return .packageInstaller }
        if externalCLIPath(cask) != nil { return .externalExecutable }
        return nil
    }

    func uninstallAvailability(for cask: Cask) -> CaskUninstallAvailability {
        if isInstalled(token: cask.token) {
            return .available
        }
        if isAdoptable(cask) {
            return .unavailable(
                reason: String(
                    localized: "Adopt this app first so CaskHub can manage/uninstall it."
                )
            )
        }
        if isMacAppStoreInstalled(cask) {
            return .unavailable(
                reason: String(localized: .stateUninstallMasInstalled)
            )
        }
        if let externalPath = externalCLIPath(cask) {
            return .unavailable(
                reason: String(localized: .stateUninstallExternalCLI(externalPath.path))
            )
        }
        return .notApplicable
    }

    func localState(for cask: Cask) -> CaskLocalState {
        let source = installationSource(for: cask)
        let externalVersion = externalApplication(for: cask)?.version
        let target = cask.updateTarget(for: platform)
        let outdated = target.map { isOutdated(token: cask.token, remoteVersion: $0.version, autoUpdates: $0.autoUpdates) } ?? false
        return CaskLocalState(
            installationSource: source,
            externalVersion: externalVersion,
            homebrewAppVersion: snapshot.installationIndex.homebrewApplications[cask.token]?.shortVersion
                .flatMap { $0.isEmpty ? nil : $0 },
            adoptionPlan: CaskAdoptionPlan.make(
                installationSource: source,
                installedVersion: externalVersion,
                homebrewVersion: cask.displayVersion,
                installedCaskTokens: Set(snapshot.installedCasks.keys),
                conflictingCaskTokens: cask.conflictsWith?.caskTokens ?? []
            ),
            externalCLIPath: source == .externalExecutable ? externalCLIPath(cask) : nil,
            uninstallAvailability: uninstallAvailability(for: cask),
            hasAvailableUpdate: outdated
                && homebrewOutdated?.pinned.contains(cask.token) != true
                && (greedyUpdates || target?.autoUpdates != true || isListedByHomebrew(cask.token)),
            isOutdated: outdated,
            isZombie: isZombie(cask),
            canOpen: canOpen(cask),
            retirement: cask.retirement(for: platform)
        )
    }

    func isOutdated(token: String, remoteVersion: String, autoUpdates: Bool?) -> Bool {
        guard let installation = snapshot.installedCasks[token],
              // brew upgrade does nothing once the receipt matches the tap.
              installation.installedVersion != remoteVersion
        else { return false }
        // Self-updaters can advance the app without updating Homebrew's receipt or its last answer.
        if autoUpdates == true,
           let application = snapshot.installationIndex.homebrewApplications[token],
           let outdated = Self.isBundleOutdated(application, tapVersion: remoteVersion) {
            return outdated
        }
        if isListedByHomebrew(token),
           !snapshot.installationIndex.verifiedZombieTokens.contains(token) {
            return true
        }
        guard !installation.isZombie else { return false }
        return Self.comparableVersion(installation.installedVersion)
            != Self.comparableVersion(remoteVersion)
    }

    func isZombie(_ cask: Cask) -> Bool {
        guard let installation = snapshot.installedCasks[cask.token],
              installation.isZombie,
              !cask.appArtifactNames.isEmpty
        else { return false }
        guard snapshot.installationIndex.catalogTokens.contains(cask.token) else {
            return false
        }
        return snapshot.installationIndex.verifiedZombieTokens.contains(
            cask.token
        )
    }

    func canOpen(_ cask: Cask) -> Bool {
        if isInstalled(token: cask.token) {
            if snapshot.installationIndex.catalogTokens.contains(cask.token) {
                return snapshot.installationIndex.launchableHomebrewTokens.contains(
                    cask.token
                )
            }
            return launchableBundleNames(for: cask).contains {
                snapshot.detectedApplicationsByBundleName[$0] != nil
            }
        }
        let hasStoreApp = snapshot.installationIndex.catalogTokens.contains(cask.token)
            ? snapshot.installationIndex.macAppStoreApplications[cask.token] != nil
            : macAppStoreApplication(for: cask) != nil
        return hasStoreApp
            || snapshot.externalApplicationOwners[cask.token] != nil
            || snapshot.externalPackageInstallations[cask.token] != nil
    }

    func launchURL(for cask: Cask) -> URL? {
        guard isInstalled(token: cask.token) else { return externalLaunchURL(for: cask) }
        return existingBundleURL(named: launchableBundleNames(for: cask))
    }

    func externalLaunchURL(for cask: Cask) -> URL? {
        externalApplication(for: cask)?.url
    }

    func externalAppVersion(for cask: Cask) -> String? {
        guard !isInstalled(token: cask.token) else { return nil }
        return externalApplication(for: cask)?.version
    }

    func installationDates(for cask: Cask) -> CaskInstallationDates? {
        snapshot.installationDatesByToken[cask.token]
    }

    func existingBundleURL(named names: [String]) -> URL? {
        if let detected = names.lazy
            .flatMap({ snapshot.detectedApplicationsByBundleName[$0] ?? [] })
            .first(where: {
                applicationDiscovery.metadata(
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

    private func isListedByHomebrew(_ token: String) -> Bool {
        homebrewOutdated?.upgradable.contains(token) == true
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

    private func externalApplication(for cask: Cask) -> DetectedApplication? {
        snapshot.externalApplicationOwners[cask.token]
            ?? snapshot.externalPackageApplicationOwners[cask.token]
            ?? macAppStoreApplication(for: cask)
    }

    private func macAppStoreApplication(for cask: Cask) -> DetectedApplication? {
        if snapshot.installationIndex.catalogTokens.contains(cask.token) {
            return snapshot.installationIndex.macAppStoreApplications[cask.token]
        }
        return cask.storeAppNames.lazy
            .flatMap { snapshot.detectedApplicationsByBundleName[$0] ?? [] }
            .first { application in
                guard application.isMacAppStore else { return false }
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
        if !cask.storeBundleIdentifiers.isEmpty {
            return ApplicationIdentityMatcher.applicationBundleIdentifier(
                identifier,
                matchesAny: cask.storeBundleIdentifiers
            )
        }
        return cask.hasPackageArtifact && cask.catalogPackageProducts == nil && ApplicationIdentityMatcher.bundleIdentifier(
            identifier,
            matchesPackageIdentifiers: cask.packageIdentifiers
        )
    }
}

private extension CaskLocalStateResolver {
    static func isBundleOutdated(_ application: DetectedApplication, tapVersion: String) -> Bool? {
        let parts = tapVersion.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let short = application.shortVersion,
              let release = numericComparison(short, parts[0])
        else { return nil }
        // The second part is only a build number when it is shaped like the bundle's.
        guard release == .orderedSame, parts.count == 2,
              let build = application.buildVersion,
              build.split(separator: ".").count == parts[1].split(separator: ".").count,
              let buildOrder = numericComparison(build, parts[1])
        else { return release == .orderedAscending }
        return buildOrder == .orderedAscending
    }

    static func numericComparison(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        guard lhs.allSatisfy({ $0.isNumber || $0 == "." }),
              rhs.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return NumericVersionComparison.compare(lhs, rhs)
    }
}
