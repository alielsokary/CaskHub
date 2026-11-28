//
//  InstallationIndexBuilder.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated struct InstallationIndexBuilder: Sendable {
    struct HomebrewApplicationState {
        let launchableTokens: Set<String>
        let zombieTokens: Set<String>
        let verifiedApplications: [String: DetectedApplication]
    }

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
                launchableBundleNames: launchableBundleNames,
                bundleIdentifiers: Set(cask.applicationBundleIdentifiers)
            )
        }
    }

    func build(
        catalog: CaskInstallationCatalog,
        applications: [DetectedApplication],
        binaryPaths: [String: URL],
        installedCasks: [String: LocalCaskInstallation],
        packageInstallations: [String: ExternalPackageInstallation] = [:]
    ) -> CaskInstallationIndex {
        let homebrewApplications = resolveHomebrewApplicationState(
            signatures: catalog.applicationSignatures,
            applications: applications,
            installedCasks: installedCasks,
            packageInstallations: packageInstallations
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
            homebrewApplications: homebrewApplications.verifiedApplications,
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
        let reviewedNames = Set(signatures.filter(\.isReviewedProduct).flatMap(\.bundleNames))
        var signaturesByBundleName: [String: [MacAppStoreCaskSignature]] = [:]
        for signature in signatures where !installedTokens.contains(signature.token) {
            for bundleName in signature.bundleNames where signature.isReviewedProduct
                || !signature.applicationBundleIdentifiers.isEmpty || !reviewedNames.contains(bundleName) {
                signaturesByBundleName[bundleName, default: []].append(signature)
            }
        }

        var result: [String: DetectedApplication] = [:]
        for application in applications where application.isMacAppStore {
            let candidates = signaturesByBundleName[application.bundleName] ?? []
            let verified = candidates.filter { macAppStoreApplication(application, matches: $0) }
            let matches = verified.isEmpty ? candidates.filter { signature in
                application.bundleIdentifier.map {
                    ApplicationIdentityMatcher.applicationBundleIdentifier($0, matchesAny: signature.hintedApplicationBundleIdentifiers)
                } ?? false
            } : verified
            // Conflicting reviewed products remain unresolved, just like receipt matching.
            guard !matches.contains(where: \.isReviewedProduct) || matches.count == 1 else { continue }
            for signature in matches where result[signature.token] == nil {
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
        installedCasks: [String: LocalCaskInstallation],
        packageInstallations: [String: ExternalPackageInstallation] = [:]
    ) -> HomebrewApplicationState {
        let signaturesByToken = Dictionary(
            signatures.map { ($0.token, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let validBundleNames = Set(applications.map(\.bundleName))
        let applicationsByName = Dictionary(grouping: applications, by: \.bundleName)
        let installedClaimsByName = Dictionary(
            grouping: signaturesByToken.values.filter { installedCasks[$0.token] != nil }.flatMap(\.currentBundleNames),
            by: { $0 }
        )
        var launchableTokens: Set<String> = []
        var zombieTokens: Set<String> = []
        var verifiedApplications: [String: DetectedApplication] = [:]

        for (token, installation) in installedCasks {
            guard let signature = signaturesByToken[token] else { continue }
            let launchableNames = Set(installation.appBundleNames)
                .union(signature.launchableBundleNames)
                .union(packageInstallations[token]?.appBundleNames ?? [])
            if !launchableNames.isDisjoint(with: validBundleNames) {
                launchableTokens.insert(token)
            }
            if installation.isZombie,
               !signature.currentBundleNames.isEmpty,
               signature.currentBundleNames.isDisjoint(with: validBundleNames) {
                zombieTokens.insert(token)
            }
            // Multiple app artifacts or copies have no unambiguous installed version.
            guard !installation.isZombie,
                  signature.currentBundleNames.count == 1,
                  let bundleName = signature.currentBundleNames.first,
                  installedClaimsByName[bundleName]?.count == 1,
                  let candidates = applicationsByName[bundleName], candidates.count == 1,
                  let application = candidates.first,
                  application.isDirectlyInApplicationDirectory,
                  !application.isMacAppStore,
                  let identifier = application.bundleIdentifier,
                  ApplicationIdentityMatcher.applicationBundleIdentifier(identifier, matchesAny: Array(signature.bundleIdentifiers))
            else { continue }
            verifiedApplications[token] = application
        }
        return HomebrewApplicationState(
            launchableTokens: launchableTokens, zombieTokens: zombieTokens,
            verifiedApplications: verifiedApplications
        )
    }

    func resolveInstallationDates(
        installedCasks: [String: LocalCaskInstallation],
        externalApplicationOwners: [String: DetectedApplication],
        macAppStoreApplications: [String: DetectedApplication],
        packageInstallations: [String: ExternalPackageInstallation],
        applications: [DetectedApplication]
    ) -> [String: CaskInstallationDates] {
        var result = installedCasks.mapValues {
            CaskInstallationDates(
                installedAt: $0.installedAt,
                lastUpdatedAt: $0.lastUpdatedAt,
                basis: .homebrewMetadata
            )
        }
        for (token, application) in macAppStoreApplications
            where result[token] == nil {
            result[token] = installationDates(for: application)
        }

        for (token, application) in resolveExternalPackageApplications(
            packageInstallations: packageInstallations,
            applications: applications
        )
            where result[token] == nil {
            result[token] = installationDates(for: application)
        }

        for (token, application) in externalApplicationOwners
            where result[token] == nil {
            result[token] = installationDates(for: application)
        }
        return result
    }

    func resolveExternalPackageApplications(
        packageInstallations: [String: ExternalPackageInstallation],
        applications: [DetectedApplication]
    ) -> [String: DetectedApplication] {
        let nonStoreApplicationsByName = Dictionary(
            grouping: applications.lazy.filter { !$0.isMacAppStore },
            by: \.bundleName
        )
        return packageInstallations.reduce(into: [:]) { result, entry in
            let (token, installation) = entry
            result[token] = installation.appBundleNames.lazy.compactMap { name in
                let candidates = nonStoreApplicationsByName[name] ?? []
                return candidates.first(where: \.isDirectlyInApplicationDirectory)
                    ?? candidates.first
            }.first
        }
    }

    private func installationDates(
        for application: DetectedApplication
    ) -> CaskInstallationDates {
        CaskInstallationDates(
            installedAt: application.installedAt,
            lastUpdatedAt: application.lastUpdatedAt,
            basis: .applicationBundleAttributes
        )
    }

    private func macAppStoreApplication(
        _ application: DetectedApplication,
        matches signature: MacAppStoreCaskSignature
    ) -> Bool {
        guard let bundleIdentifier = application.bundleIdentifier else { return false }
        if !signature.applicationBundleIdentifiers.isEmpty {
            return ApplicationIdentityMatcher.storeApplication(
                bundleIdentifier,
                isIPhoneIPadApp: application.isIPhoneIPadApp,
                matchesAny: signature.applicationBundleIdentifiers
            )
        }
        return signature.hasPackageArtifact && ApplicationIdentityMatcher.bundleIdentifier(
            bundleIdentifier,
            matchesPackageIdentifiers: signature.packageIdentifiers
        )
    }
}
