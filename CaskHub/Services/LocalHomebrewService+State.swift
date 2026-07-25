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

    /// The cask is present on this Mac, regardless of which installer owns it.
    func isPresent(_ cask: Cask) -> Bool {
        installedCasks[cask.token] != nil
            || isMacAppStoreInstalled(cask)
            || isAdoptable(cask)
            || externalCLIPath(cask) != nil
    }

    /// The cask isn't brew-managed, but its app already sits in /Applications
    /// or was installed by a package that Homebrew can reinstall and manage.
    func isAdoptable(_ cask: Cask) -> Bool {
        isAdoptableApplication(cask) || isExternalPackageInstalled(cask)
    }

    func isAdoptableApplication(_ cask: Cask) -> Bool {
        guard installedCasks[cask.token] == nil else { return false }
        if !applicationCaskSignatures.isEmpty {
            return externalApplicationOwners[cask.token] != nil
        }

        // Catalog-less fallback for previews and isolated state injection.
        return cask.appArtifactNames.contains(where: externalAppNames.contains)
    }

    func isExternalPackageInstalled(_ cask: Cask) -> Bool {
        installedCasks[cask.token] == nil
            && externalPackageInstallations[cask.token] != nil
    }

    /// Mac App Store apps are present, but adopting them would break Store updates.
    func isMacAppStoreInstalled(_ cask: Cask) -> Bool {
        guard installedCasks[cask.token] == nil else { return false }
        if installationIndex.catalogTokens.contains(cask.token) {
            return installationIndex.macAppStoreApplications[cask.token] != nil
        }
        if macAppStoreApplication(for: cask) != nil { return true }

        // Keep the name-indexed fallback for state injected by previews and tests.
        let matchingNames = Set(cask.appArtifactNames + cask.packageAppNameCandidates)
            .intersection(macAppStoreAppNames)
        guard !matchingNames.isEmpty else { return false }

        guard cask.hasPackageArtifact else { return true }
        return matchingNames.contains { appName in
            macAppStoreBundleIdentifiers[appName]?.contains { bundleIdentifier in
                storeBundleIdentifier(bundleIdentifier, matches: cask)
            } == true
        }
    }

    /// A CLI cask whose tool is on the device via some other installer
    /// (e.g. claude-code's native install script). Detected, not managed.
    func externalCLIPath(_ cask: Cask) -> URL? {
        guard installedCasks[cask.token] == nil else { return nil }
        if installationIndex.catalogTokens.contains(cask.token) {
            return installationIndex.externalCLIPaths[cask.token]
        }
        return cask.binaryArtifactNames.lazy.compactMap { self.externalBinaryPaths[$0] }.first
    }

    nonisolated static func buildInstallationIndex(
        catalog: CaskInstallationCatalog,
        applications: [DetectedApplication],
        binaryPaths: [String: URL],
        installedCasks: [String: LocalCaskInstallation]
    ) -> CaskInstallationIndex {
        CaskInstallationIndex(
            catalogTokens: catalog.tokens,
            macAppStoreApplications: resolveMacAppStoreApplications(
                signatures: catalog.macAppStoreSignatures,
                applications: applications,
                installedCasks: installedCasks
            ),
            externalCLIPaths: resolveExternalCLIPaths(
                signatures: catalog.binarySignatures,
                binaryPaths: binaryPaths,
                installedCasks: installedCasks
            )
        )
    }

    nonisolated static func resolveMacAppStoreApplications(
        signatures: [MacAppStoreCaskSignature],
        applications: [DetectedApplication],
        installedCasks: [String: LocalCaskInstallation]
    ) -> [String: DetectedApplication] {
        let installedTokens = Set(installedCasks.keys)
        var signaturesByBundleName: [String: [MacAppStoreCaskSignature]] = [:]
        for signature in signatures where !installedTokens.contains(signature.token) {
            for bundleName in signature.bundleNames {
                signaturesByBundleName[bundleName, default: []].append(signature)
            }
        }

        var result: [String: DetectedApplication] = [:]
        for application in applications where application.isMacAppStore {
            for signature in signaturesByBundleName[application.bundleName] ?? []
                where result[signature.token] == nil
                    && macAppStoreApplication(application, matches: signature) {
                result[signature.token] = application
            }
        }
        return result
    }

    nonisolated static func resolveExternalCLIPaths(
        signatures: [BinaryCaskSignature],
        binaryPaths: [String: URL],
        installedCasks: [String: LocalCaskInstallation]
    ) -> [String: URL] {
        let installedTokens = Set(installedCasks.keys)
        return signatures.reduce(into: [:]) { result, signature in
            guard !installedTokens.contains(signature.token),
                  let path = signature.binaryNames.lazy.compactMap({ binaryPaths[$0] }).first
            else { return }
            result[signature.token] = path
        }
    }

    private nonisolated static func macAppStoreApplication(
        _ application: DetectedApplication,
        matches signature: MacAppStoreCaskSignature
    ) -> Bool {
        guard signature.hasPackageArtifact else { return true }
        guard let bundleIdentifier = application.bundleIdentifier else { return false }
        if !signature.applicationBundleIdentifiers.isEmpty {
            return applicationBundleIdentifier(
                bundleIdentifier,
                matchesAny: signature.applicationBundleIdentifiers
            )
        }
        return Self.bundleIdentifier(
            bundleIdentifier,
            matchesPackageIdentifiers: signature.packageIdentifiers
        )
    }

    func installationSource(for cask: Cask) -> CaskInstallationSource? {
        if installedCasks[cask.token] != nil { return .homebrew }
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
                reason: "Installed from the Mac App Store. Uninstall it from Finder or Launchpad."
            )
        }
        if let externalPath = externalCLIPath(cask) {
            return .unavailable(
                reason: "Installed outside Homebrew at \(externalPath.path). "
                    + "Remove or move that file manually before installing the Homebrew version."
            )
        }
        return .notApplicable
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
        openBundle(named: launchableBundleNames(for: cask), token: cask.token)
    }

    func canOpen(_ cask: Cask) -> Bool {
        if installedCasks[cask.token] == nil,
           let application = macAppStoreApplication(for: cask) {
            return Self.applicationBundleMetadata(
                at: application.url, fileManager: fileManager
            ) != nil
        }
        return existingBundleURL(named: launchableBundleNames(for: cask)) != nil
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
        if let application = macAppStoreApplication(for: cask) {
            appLauncher(application.url)
            return
        }
        if let application = externalApplicationOwners[cask.token] {
            appLauncher(application.url)
            return
        }
        openBundle(named: externalBundleNameCandidates(for: cask), token: cask.token)
    }

    /// Version of a not-yet-adopted app, read from its bundle's Info.plist.
    func externalAppVersion(for cask: Cask) -> String? {
        guard installedCasks[cask.token] == nil,
              installationSource(for: cask) != nil,
              let appURL = macAppStoreApplication(for: cask)?.url
                ?? externalApplicationOwners[cask.token]?.url
                ?? existingBundleURL(named: externalBundleNameCandidates(for: cask)),
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

    private func launchableBundleNames(for cask: Cask) -> [String] {
        let receiptNames = installedCasks[cask.token]?.appBundleNames ?? []
        return receiptNames + externalBundleNameCandidates(for: cask)
    }

    private func externalBundleNameCandidates(for cask: Cask) -> [String] {
        let packageNames = externalPackageInstallations[cask.token]?.appBundleNames ?? []
        return packageNames + cask.appArtifactNames + cask.packageAppNameCandidates
    }

    private func macAppStoreApplication(for cask: Cask) -> DetectedApplication? {
        if installationIndex.catalogTokens.contains(cask.token) {
            return installationIndex.macAppStoreApplications[cask.token]
        }
        let matchingNames = Set(cask.appArtifactNames + cask.packageAppNameCandidates)
        return detectedApplications.first { application in
            guard application.isMacAppStore,
                  matchingNames.contains(application.bundleName)
            else { return false }
            guard cask.hasPackageArtifact else { return true }
            guard let bundleIdentifier = application.bundleIdentifier else { return false }
            return storeBundleIdentifier(bundleIdentifier, matches: cask)
        }
    }

    /// App bundle IDs are stronger identity evidence than installer receipt IDs.
    /// Direct and App Store variants commonly keep the product prefix and vary
    /// only their final channel/platform component (macsys versus macos).
    private func storeBundleIdentifier(_ identifier: String, matches cask: Cask) -> Bool {
        if !cask.applicationBundleIdentifiers.isEmpty {
            return Self.applicationBundleIdentifier(
                identifier, matchesAny: cask.applicationBundleIdentifiers
            )
        }
        return Self.bundleIdentifier(
            identifier, matchesPackageIdentifiers: cask.packageIdentifiers
        )
    }

    nonisolated static func applicationBundleIdentifier(
        _ identifier: String,
        matchesAny candidates: [String]
    ) -> Bool {
        let actual = identifier.lowercased().split(separator: ".").map(String.init)
        return candidates.contains { candidate in
            let expected = candidate.lowercased().split(separator: ".").map(String.init)
            if actual == expected { return true }
            return zip(actual, expected).prefix { pair in
                pair.0 == pair.1
            }.count >= 3
        }
    }

    nonisolated static func bundleIdentifier(
        _ bundleIdentifier: String,
        matchesPackageIdentifiers packageIdentifiers: [String]
    ) -> Bool {
        guard let bundleVendor = reverseDNSVendorPrefix(bundleIdentifier) else { return false }
        return packageIdentifiers.contains {
            reverseDNSVendorPrefix($0) == bundleVendor
        }
    }

    private nonisolated static func reverseDNSVendorPrefix(_ identifier: String) -> String? {
        let components = identifier.lowercased().split(separator: ".")
        guard components.count >= 2 else { return nil }
        return components.prefix(2).joined(separator: ".")
    }

    func existingBundleURL(named names: [String]) -> URL? {
        let nameSet = Set(names)
        if let detected = detectedApplications.first(where: {
            nameSet.contains($0.bundleName)
                && Self.applicationBundleMetadata(at: $0.url, fileManager: fileManager) != nil
        }) {
            return detected.url
        }

        return names.flatMap { name in
            applicationDirectories.map { $0.appendingPathComponent(name) }
        }
        .first { Self.applicationBundleMetadata(at: $0, fileManager: fileManager) != nil }
    }
}
