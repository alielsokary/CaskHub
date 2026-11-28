//
//  CaskLocalStateResolver.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated struct CaskLocalStateResolver: Sendable {
    let snapshot: InstallationSnapshot
    let hasRegisteredApplicationCatalog: Bool
    let greedyUpdates: Bool
    let homebrewOutdated: HomebrewOutdatedReport?
    let platform: CaskPlatform?
    let applicationDirectories: [URL]
    /// Only launch-URL lookups touch it; FileManager is documented thread-safe for those reads.
    nonisolated(unsafe) let fileManager: FileManager

    private let applicationDiscovery = ApplicationDiscovery()

    func isInstalled(token reference: String) -> Bool {
        snapshot.installation(for: reference) != nil
    }

    func isAdoptable(_ cask: Cask) -> Bool {
        isAdoptableApplication(cask) || isExternalPackageInstalled(cask)
    }

    func isAdoptableApplication(_ cask: Cask) -> Bool {
        guard detectsExternalInstalls(cask), !isInstalled(token: cask.reference) else { return false }
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
        detectsExternalInstalls(cask) && !isInstalled(token: cask.reference)
            && snapshot.externalPackageInstallations[cask.token] != nil
    }

    func isMacAppStoreInstalled(_ cask: Cask) -> Bool {
        guard detectsExternalInstalls(cask), !isInstalled(token: cask.reference) else { return false }
        if snapshot.installationIndex.catalogTokens.contains(cask.token) {
            return snapshot.installationIndex.macAppStoreApplications[cask.token] != nil
        }
        if macAppStoreApplication(for: cask) != nil { return true }

        let matchingNames = Set(cask.storeAppNames)
        .intersection(snapshot.macAppStoreAppNames)
        guard !matchingNames.isEmpty else { return false }

        return matchingNames.contains { appName in
            snapshot.macAppStoreBundleIdentifiers[appName]?.contains {
                storeBundleIdentifier($0, isIPhoneIPadApp: false, matches: cask)
            } == true
        }
    }

    func externalCLIPath(_ cask: Cask) -> URL? {
        guard detectsExternalInstalls(cask), !isInstalled(token: cask.reference) else { return nil }
        if snapshot.installationIndex.catalogTokens.contains(cask.token) {
            return snapshot.installationIndex.externalCLIPaths[cask.token]
        }
        return cask.binaryArtifactNames.lazy.compactMap {
            snapshot.externalBinaryPaths[$0]
        }
        .first
    }

    func installationSource(for cask: Cask) -> CaskInstallationSource? {
        if isInstalled(token: cask.reference) { return .homebrew }
        if isMacAppStoreInstalled(cask) { return .macAppStore }
        if isAdoptableApplication(cask) { return .externalApplication }
        if isExternalPackageInstalled(cask) { return .packageInstaller }
        if externalCLIPath(cask) != nil { return .externalExecutable }
        return nil
    }

    func uninstallAvailability(for cask: Cask) -> CaskUninstallAvailability {
        if isInstalled(token: cask.reference) {
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
        let outdated = isOutdated(cask, target: target)
        let ownsInstallation = source == .homebrew
        return CaskLocalState(
            installationSource: source,
            externalVersion: externalVersion,
            homebrewAppVersion: ownsInstallation
                ? snapshot.installationIndex.homebrewApplications[cask.token]?.shortVersion.flatMap { $0.isEmpty ? nil : $0 }
                : nil,
            adoptionPlan: CaskAdoptionPlan.make(
                installationSource: source,
                installedVersion: externalVersion,
                homebrewVersion: cask.displayVersion,
                // Dictionary keys answer contains in O(1); a Set here was rebuilt for every catalog cask.
                installedCaskTokens: snapshot.installedCasks.keys,
                conflictingCaskTokens: cask.conflictsWith?.caskTokens ?? []
            ),
            externalCLIPath: source == .externalExecutable ? externalCLIPath(cask) : nil,
            uninstallAvailability: uninstallAvailability(for: cask),
            hasAvailableUpdate: outdated && offersUpdate(cask, target: target),
            isOutdated: outdated,
            isZombie: isZombie(cask),
            canOpen: canOpen(cask),
            isIPhoneIPadApp: source == .macAppStore && macAppStoreApplication(for: cask)?.isIPhoneIPadApp == true,
            retirement: cask.retirement(for: platform),
            foreignInstallationSource: snapshot.foreignInstallationSource(for: cask.reference)
        )
    }

    func isOutdated(token reference: String, remoteVersion: String, autoUpdates: Bool?) -> Bool {
        let token = CaskReference.bareToken(reference)
        guard let installation = snapshot.installation(for: reference),
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
        guard let installation = snapshot.installation(for: cask.reference),
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
        if isInstalled(token: cask.reference) {
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
        guard isInstalled(token: cask.reference) else { return externalLaunchURL(for: cask) }
        return existingBundleURL(named: launchableBundleNames(for: cask)) ?? renamedBundleURL(for: cask)
    }

    func externalLaunchURL(for cask: Cask) -> URL? {
        externalApplication(for: cask)?.url
    }

    func externalAppVersion(for cask: Cask) -> String? {
        guard !isInstalled(token: cask.reference) else { return nil }
        return externalApplication(for: cask)?.version
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

    private func launchableBundleNames(for cask: Cask) -> [String] {
        let receiptNames = snapshot.installation(for: cask.reference)?.appBundleNames ?? []
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
        guard detectsExternalInstalls(cask) else { return nil }
        return snapshot.externalApplicationOwners[cask.token]
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
                return storeBundleIdentifier(bundleIdentifier, isIPhoneIPadApp: application.isIPhoneIPadApp, matches: cask)
            }
    }

    private func storeBundleIdentifier(
        _ identifier: String,
        isIPhoneIPadApp: Bool,
        matches cask: Cask
    ) -> Bool {
        if !cask.storeBundleIdentifiers.isEmpty {
            return ApplicationIdentityMatcher.storeApplication(
                identifier,
                isIPhoneIPadApp: isIPhoneIPadApp,
                matchesAny: cask.storeBundleIdentifiers
            )
        }
        return cask.hasPackageArtifact && cask.catalogPackageProducts == nil && ApplicationIdentityMatcher.bundleIdentifier(
            identifier,
            matchesPackageIdentifiers: cask.packageIdentifiers
        )
    }
}

nonisolated extension CaskLocalStateResolver {
    func installationDates(for cask: Cask) -> CaskInstallationDates? {
        guard snapshot.foreignInstallationSource(for: cask.reference) == nil else { return nil }
        return snapshot.installationDatesByToken[cask.token]
    }
}

nonisolated private extension CaskLocalStateResolver {
    /// Tap casks never claim apps installed outside Homebrew.
    func detectsExternalInstalls(_ cask: Cask) -> Bool {
        CaskReference.isOfficial(tap: cask.tap)
    }

    func isOutdated(_ cask: Cask, target: CaskUpdateTarget?) -> Bool {
        guard CaskReference.isOfficial(tap: cask.tap) else {
            // Tap versions read as text are unreliable; brew outdated is the authority.
            return isInstalled(token: cask.reference) && isListedByHomebrew(cask.reference)
        }
        return target.map { isOutdated(token: cask.reference, remoteVersion: $0.version, autoUpdates: $0.autoUpdates) } ?? false
    }

    func offersUpdate(_ cask: Cask, target: CaskUpdateTarget?) -> Bool {
        snapshot.pinnedVersions[cask.token] == nil
            && homebrewOutdated?.pinned.contains(cask.token) != true
            && (greedyUpdates || target?.autoUpdates != true || isListedByHomebrew(cask.reference))
    }

    func isListedByHomebrew(_ reference: String) -> Bool {
        homebrewOutdated?.upgradable.contains(CaskReference.bareToken(reference)) == true
    }

    static func comparableVersion(_ version: String) -> Substring {
        version.prefix { $0 != "," && $0 != "_" }
    }

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

extension CaskLocalStateResolver {
    /// An app that renamed itself on update keeps its bundle identifier. Only called when Open is pressed.
    private func renamedBundleURL(for cask: Cask) -> URL? {
        let applications = snapshot.detectedApplicationsByBundleName.values.joined()
        for identifiers in [cask.applicationBundleIdentifiers, cask.bundleIdentifierHints] where !identifiers.isEmpty {
            let match = applications.first { application in
                application.bundleIdentifier.map {
                    ApplicationIdentityMatcher.applicationBundleIdentifier($0, matchesAny: identifiers)
                } == true && applicationDiscovery.metadata(at: application.url, fileManager: fileManager) != nil
            }
            if let match { return match.url }
        }
        return nil
    }
}
