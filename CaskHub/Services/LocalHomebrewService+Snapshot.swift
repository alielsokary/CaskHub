//
//  LocalHomebrewService+Snapshot.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

extension LocalHomebrewService {
    func installedSoftwareScanRequest() -> InstalledSoftwareScanRequest {
        InstalledSoftwareScanRequest(
            applicationDirectories: applicationDirectories,
            caskroomURL: configuredCaskroomURL(),
            catalog: installationCatalog,
            applicationSignatures: applicationCaskSignatures,
            packageSignatures: packageCaskSignatures
        )
    }

    var installedCasks: [String: LocalCaskInstallation] {
        installationSnapshot.installedCasks
    }

    var externalAppNames: Set<String> {
        installationSnapshot.externalAppNames
    }

    var externalApplicationOwners: [String: DetectedApplication] {
        installationSnapshot.externalApplicationOwners
    }

    var macAppStoreAppNames: Set<String> {
        installationSnapshot.macAppStoreAppNames
    }

    var macAppStoreBundleIdentifiers: [String: Set<String>] {
        installationSnapshot.macAppStoreBundleIdentifiers
    }

    var detectedApplications: [DetectedApplication] {
        installationSnapshot.detectedApplications
    }

    var externalBinaryPaths: [String: URL] {
        installationSnapshot.externalBinaryPaths
    }

    var externalPackageInstallations: [String: ExternalPackageInstallation] {
        installationSnapshot.externalPackageInstallations
    }

    var installationIndex: CaskInstallationIndex {
        installationSnapshot.installationIndex
    }

    var lastRefresh: Date? {
        installationSnapshot.scannedAt
    }
}
