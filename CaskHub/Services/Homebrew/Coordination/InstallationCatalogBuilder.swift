//
//  InstallationCatalogBuilder.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated struct InstallationCatalogRegistration: Sendable {
    let displayNames: [String: String]
    let applicationSignatures: [ApplicationCaskSignature]
    let installationCatalog: CaskInstallationCatalog
    let packageSignatures: [PackageCaskSignature]
}

nonisolated struct InstallationCatalogBuilder: Sendable {
    /// Every API cask verifies its own Homebrew install. Only browsable casks claim
    /// external apps: a retired token sharing a bundle ID would make ownership ambiguous.
    @MainActor
    func build(_ casks: [Cask]) -> InstallationCatalogRegistration {
        let browsable = casks.filter(\.isBrowsable)
        return InstallationCatalogRegistration(
            displayNames: casks.reduce(into: [:]) { names, cask in
                names[cask.token] = cask.displayName
            },
            applicationSignatures: makeExternalApplicationSignatures(browsable),
            installationCatalog: CaskInstallationCatalog(
                tokens: Set(casks.map(\.token)),
                macAppStoreSignatures: makeStoreSignatures(browsable),
                binarySignatures: makeBinarySignatures(browsable),
                applicationSignatures: InstallationIndexBuilder()
                    .makeApplicationSignatures(casks)
            ),
            packageSignatures: makePackageSignatures(browsable)
        )
    }

    @MainActor
    private func makeExternalApplicationSignatures(
        _ casks: [Cask]
    ) -> [ApplicationCaskSignature] {
        casks.compactMap { cask -> ApplicationCaskSignature? in
            guard !cask.appArtifactNames.isEmpty else { return nil }
            return ApplicationCaskSignature(
                token: cask.token,
                appBundleNames: Set(cask.appArtifactNames),
                bundleIdentifiers: Set(cask.applicationBundleIdentifiers)
            )
        }
    }

    @MainActor
    private func makeStoreSignatures(
        _ casks: [Cask]
    ) -> [MacAppStoreCaskSignature] {
        casks.compactMap { cask -> MacAppStoreCaskSignature? in
            let bundleNames = Set(cask.storeAppNames)
            guard !bundleNames.isEmpty else { return nil }
            return MacAppStoreCaskSignature(
                token: cask.token,
                bundleNames: bundleNames,
                hasPackageArtifact: cask.hasPackageArtifact && cask.catalogPackageProducts == nil,
                isReviewedProduct: cask.catalogPackageProducts != nil,
                applicationBundleIdentifiers: cask.storeBundleIdentifiers,
                packageIdentifiers: cask.packageIdentifiers
            )
        }
    }

    @MainActor
    private func makeBinarySignatures(
        _ casks: [Cask]
    ) -> [BinaryCaskSignature] {
        casks.compactMap { cask -> BinaryCaskSignature? in
            guard !cask.binaryArtifactNames.isEmpty else { return nil }
            return BinaryCaskSignature(
                token: cask.token,
                binaryNames: cask.binaryArtifactNames
            )
        }
    }

    @MainActor
    private func makePackageSignatures(
        _ casks: [Cask]
    ) -> [PackageCaskSignature] {
        casks.compactMap { cask -> PackageCaskSignature? in
            guard cask.hasPackageArtifact,
                  !cask.packageIdentifiers.isEmpty
            else { return nil }
            return PackageCaskSignature(
                token: cask.token,
                displayName: cask.displayName,
                receiptPatterns: cask.packageIdentifiers,
                appNameCandidates: cask.packageAppNameCandidates,
                verifiedBundleIdentifiersByName: cask.catalogPackageAppIdentifiers ?? [:],
                receiptCandidates: cask.catalogPackageCandidates ?? [],
                productIdentities: cask.catalogPackageProducts
            )
        }
    }
}
