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
    @MainActor
    func build(_ casks: [Cask]) -> InstallationCatalogRegistration {
        InstallationCatalogRegistration(
            displayNames: casks.reduce(into: [:]) { names, cask in
                names[cask.token] = cask.displayName
            },
            applicationSignatures: makeExternalApplicationSignatures(casks),
            installationCatalog: CaskInstallationCatalog(
                tokens: Set(casks.map(\.token)),
                macAppStoreSignatures: makeStoreSignatures(casks),
                binarySignatures: makeBinarySignatures(casks),
                applicationSignatures: InstallationIndexBuilder()
                    .makeApplicationSignatures(casks)
            ),
            packageSignatures: makePackageSignatures(casks)
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
            let bundleNames = Set(
                cask.appArtifactNames + cask.packageAppNameCandidates
            )
            guard !bundleNames.isEmpty else { return nil }
            return MacAppStoreCaskSignature(
                token: cask.token,
                bundleNames: bundleNames,
                hasPackageArtifact: cask.hasPackageArtifact,
                applicationBundleIdentifiers: cask.applicationBundleIdentifiers,
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
                appNameCandidates: cask.packageAppNameCandidates
            )
        }
    }
}
