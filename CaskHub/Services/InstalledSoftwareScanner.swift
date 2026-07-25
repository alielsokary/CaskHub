//
//  InstalledSoftwareScanner.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated struct InstalledSoftwareScanRequest: Sendable {
    let applicationDirectories: [URL]
    let caskroomURL: URL?
    let catalog: CaskInstallationCatalog
    let applicationSignatures: [ApplicationCaskSignature]
    let packageSignatures: [PackageCaskSignature]
}

nonisolated protocol InstalledSoftwareScanning: Sendable {
    func scan(_ request: InstalledSoftwareScanRequest) async -> InstallationSnapshot

    func reconcileCatalog(
        _ request: InstalledSoftwareScanRequest,
        with current: InstallationSnapshot
    ) async -> InstallationSnapshot
}

nonisolated struct SystemInstalledSoftwareScanner: InstalledSoftwareScanning {
    private struct ScanComponents: Sendable {
        let applications: ExternalApplicationScan
        let installedCasks: [String: LocalCaskInstallation]
        let binaryPaths: [String: URL]
        let packages: [String: ExternalPackageInstallation]
    }

    func scan(_ request: InstalledSoftwareScanRequest) async -> InstallationSnapshot {
        // FileManager enumeration and pkgutil are synchronous. This task owns a
        // complete independent scan and returns one Sendable value to MainActor.
        return await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let applications = LocalHomebrewService.scanApplications(
                fileManager: fileManager,
                directories: request.applicationDirectories
            )
            let installedCasks = request.caskroomURL.map {
                LocalHomebrewService.scanCaskroom(
                    at: $0,
                    fileManager: fileManager,
                    applicationDirectories: request.applicationDirectories
                )
            } ?? [:]
            let binaryPaths = LocalHomebrewService.scanBinaryDirectories(
                fileManager: fileManager
            )
            let packages = LocalHomebrewService.scanExternalPackageInstallations(
                signatures: request.packageSignatures,
                availableAppNames: applications.nonStoreNames
            )
            let components = ScanComponents(
                applications: applications,
                installedCasks: installedCasks,
                binaryPaths: binaryPaths,
                packages: packages
            )
            return Self.makeSnapshot(
                request: request,
                current: nil,
                components: components
            )
        }.value
    }

    func reconcileCatalog(
        _ request: InstalledSoftwareScanRequest,
        with current: InstallationSnapshot
    ) async -> InstallationSnapshot {
        // Catalog reconciliation only needs applications and package receipts;
        // it reuses the current Caskroom and binary scan.
        return await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let applications = LocalHomebrewService.scanApplications(
                fileManager: fileManager,
                directories: request.applicationDirectories
            )
            let packages = request.packageSignatures.isEmpty ? [:] :
                LocalHomebrewService.scanExternalPackageInstallations(
                    signatures: request.packageSignatures,
                    availableAppNames: applications.nonStoreNames
                )
            let components = ScanComponents(
                applications: applications,
                installedCasks: current.installedCasks,
                binaryPaths: current.externalBinaryPaths,
                packages: packages
            )
            return Self.makeSnapshot(
                request: request,
                current: current,
                components: components
            )
        }.value
    }

    private static func makeSnapshot(
        request: InstalledSoftwareScanRequest,
        current: InstallationSnapshot?,
        components: ScanComponents
    ) -> InstallationSnapshot {
        let owners = LocalHomebrewService.resolveExternalApplicationOwners(
            signatures: request.applicationSignatures,
            applications: components.applications.applications,
            installedCasks: components.installedCasks
        )
        let index = LocalHomebrewService.buildInstallationIndex(
            catalog: request.catalog,
            applications: components.applications.applications,
            binaryPaths: components.binaryPaths,
            installedCasks: components.installedCasks
        )
        return InstallationSnapshot(
            installedCasks: components.installedCasks,
            externalAppNames: components.applications.adoptableNames,
            externalApplicationOwners: owners,
            macAppStoreAppNames: components.applications.macAppStoreNames,
            macAppStoreBundleIdentifiers:
                components.applications.macAppStoreBundleIdentifiers,
            detectedApplications: components.applications.applications,
            externalBinaryPaths: components.binaryPaths,
            externalPackageInstallations: components.packages,
            installationIndex: index,
            scannedAt: current?.scannedAt ?? .now
        )
    }
}
