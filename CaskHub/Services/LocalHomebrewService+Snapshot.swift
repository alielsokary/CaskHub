//
//  LocalHomebrewService+Snapshot.swift
//  CaskHub
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
        get { installationSnapshot.installedCasks }
        set { replaceInstallationSnapshot(installedCasks: newValue) }
    }

    var externalAppNames: Set<String> {
        get { installationSnapshot.externalAppNames }
        set { replaceInstallationSnapshot(externalAppNames: newValue) }
    }

    var externalApplicationOwners: [String: DetectedApplication] {
        get { installationSnapshot.externalApplicationOwners }
        set { replaceInstallationSnapshot(externalApplicationOwners: newValue) }
    }

    var macAppStoreAppNames: Set<String> {
        get { installationSnapshot.macAppStoreAppNames }
        set { replaceInstallationSnapshot(macAppStoreAppNames: newValue) }
    }

    var macAppStoreBundleIdentifiers: [String: Set<String>] {
        get { installationSnapshot.macAppStoreBundleIdentifiers }
        set { replaceInstallationSnapshot(macAppStoreBundleIdentifiers: newValue) }
    }

    var detectedApplications: [DetectedApplication] {
        get { installationSnapshot.detectedApplications }
        set { replaceInstallationSnapshot(detectedApplications: newValue) }
    }

    var externalBinaryPaths: [String: URL] {
        get { installationSnapshot.externalBinaryPaths }
        set { replaceInstallationSnapshot(externalBinaryPaths: newValue) }
    }

    var externalPackageInstallations: [String: ExternalPackageInstallation] {
        get { installationSnapshot.externalPackageInstallations }
        set { replaceInstallationSnapshot(externalPackageInstallations: newValue) }
    }

    var installationIndex: CaskInstallationIndex {
        get { installationSnapshot.installationIndex }
        set { replaceInstallationSnapshot(installationIndex: newValue) }
    }

    var lastRefresh: Date? {
        installationSnapshot.scannedAt
    }

    private func replaceInstallationSnapshot(
        installedCasks: [String: LocalCaskInstallation]? = nil,
        externalAppNames: Set<String>? = nil,
        externalApplicationOwners: [String: DetectedApplication]? = nil,
        macAppStoreAppNames: Set<String>? = nil,
        macAppStoreBundleIdentifiers: [String: Set<String>]? = nil,
        detectedApplications: [DetectedApplication]? = nil,
        externalBinaryPaths: [String: URL]? = nil,
        externalPackageInstallations: [String: ExternalPackageInstallation]? = nil,
        installationIndex: CaskInstallationIndex? = nil
    ) {
        let current = installationSnapshot
        commitInstallationSnapshot(InstallationSnapshot(
            installedCasks: installedCasks ?? current.installedCasks,
            externalAppNames: externalAppNames ?? current.externalAppNames,
            externalApplicationOwners:
                externalApplicationOwners ?? current.externalApplicationOwners,
            macAppStoreAppNames: macAppStoreAppNames ?? current.macAppStoreAppNames,
            macAppStoreBundleIdentifiers:
                macAppStoreBundleIdentifiers ?? current.macAppStoreBundleIdentifiers,
            detectedApplications: detectedApplications ?? current.detectedApplications,
            externalBinaryPaths: externalBinaryPaths ?? current.externalBinaryPaths,
            externalPackageInstallations:
                externalPackageInstallations ?? current.externalPackageInstallations,
            installationIndex: installationIndex ?? current.installationIndex,
            scannedAt: current.scannedAt
        ))
    }
}
