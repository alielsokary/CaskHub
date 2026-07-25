//
//  InstallationIndexBuilder.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated struct InstallationIndexBuilder: Sendable {
    @MainActor
    func makeApplicationSignatures(
        _ casks: [Cask]
    ) -> [CaskApplicationSignature] {
        casks.compactMap { cask in
            let currentBundleNames = Set(cask.appArtifactNames)
            let launchableBundleNames = Set(
                cask.appArtifactNames + cask.packageAppNameCandidates
            )
            guard !currentBundleNames.isEmpty || !launchableBundleNames.isEmpty else {
                return nil
            }
            return CaskApplicationSignature(
                token: cask.token,
                currentBundleNames: currentBundleNames,
                launchableBundleNames: launchableBundleNames
            )
        }
    }

    func build(
        catalog: CaskInstallationCatalog,
        applications: [DetectedApplication],
        binaryPaths: [String: URL],
        installedCasks: [String: LocalCaskInstallation]
    ) -> CaskInstallationIndex {
        let homebrewApplications = resolveHomebrewApplicationState(
            signatures: catalog.applicationSignatures,
            applications: applications,
            installedCasks: installedCasks
        )
        return CaskInstallationIndex(
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
            ),
            launchableHomebrewTokens: homebrewApplications.launchableTokens,
            verifiedZombieTokens: homebrewApplications.zombieTokens
        )
    }

    func resolveMacAppStoreApplications(
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

    func resolveExternalCLIPaths(
        signatures: [BinaryCaskSignature],
        binaryPaths: [String: URL],
        installedCasks: [String: LocalCaskInstallation]
    ) -> [String: URL] {
        let installedTokens = Set(installedCasks.keys)
        return signatures.reduce(into: [:]) { result, signature in
            guard !installedTokens.contains(signature.token),
                  let path = signature.binaryNames.lazy.compactMap({
                      binaryPaths[$0]
                  }).first
            else { return }
            result[signature.token] = path
        }
    }

    func resolveHomebrewApplicationState(
        signatures: [CaskApplicationSignature],
        applications: [DetectedApplication],
        installedCasks: [String: LocalCaskInstallation]
    ) -> (launchableTokens: Set<String>, zombieTokens: Set<String>) {
        let signaturesByToken = Dictionary(
            signatures.map { ($0.token, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let validBundleNames = Set(applications.map(\.bundleName))
        var launchableTokens: Set<String> = []
        var zombieTokens: Set<String> = []

        for (token, installation) in installedCasks {
            guard let signature = signaturesByToken[token] else { continue }
            let launchableNames = Set(installation.appBundleNames)
                .union(signature.launchableBundleNames)
            if !launchableNames.isDisjoint(with: validBundleNames) {
                launchableTokens.insert(token)
            }
            if installation.isZombie,
               !signature.currentBundleNames.isEmpty,
               signature.currentBundleNames.isDisjoint(with: validBundleNames) {
                zombieTokens.insert(token)
            }
        }
        return (launchableTokens, zombieTokens)
    }

    private func macAppStoreApplication(
        _ application: DetectedApplication,
        matches signature: MacAppStoreCaskSignature
    ) -> Bool {
        guard signature.hasPackageArtifact else { return true }
        guard let bundleIdentifier = application.bundleIdentifier else { return false }
        if !signature.applicationBundleIdentifiers.isEmpty {
            return ApplicationIdentityMatcher.applicationBundleIdentifier(
                bundleIdentifier,
                matchesAny: signature.applicationBundleIdentifiers
            )
        }
        return ApplicationIdentityMatcher.bundleIdentifier(
            bundleIdentifier,
            matchesPackageIdentifiers: signature.packageIdentifiers
        )
    }
}
