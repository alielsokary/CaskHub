//
//  InstallationSnapshot.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated struct InstallationSnapshot: Sendable {
    let installedCasks: [String: LocalCaskInstallation]
    let externalAppNames: Set<String>
    let externalApplicationOwners: [String: DetectedApplication]
    let macAppStoreAppNames: Set<String>
    let macAppStoreBundleIdentifiers: [String: Set<String>]
    let detectedApplications: [DetectedApplication]
    let externalBinaryPaths: [String: URL]
    let externalPackageInstallations: [String: ExternalPackageInstallation]
    let installationIndex: CaskInstallationIndex
    let scannedAt: Date?

    init(
        installedCasks: [String: LocalCaskInstallation] = [:],
        externalAppNames: Set<String> = [],
        externalApplicationOwners: [String: DetectedApplication] = [:],
        macAppStoreAppNames: Set<String> = [],
        macAppStoreBundleIdentifiers: [String: Set<String>] = [:],
        detectedApplications: [DetectedApplication] = [],
        externalBinaryPaths: [String: URL] = [:],
        externalPackageInstallations: [String: ExternalPackageInstallation] = [:],
        installationIndex: CaskInstallationIndex = .empty,
        scannedAt: Date? = nil
    ) {
        self.installedCasks = installedCasks
        self.externalAppNames = externalAppNames
        self.externalApplicationOwners = externalApplicationOwners
        self.macAppStoreAppNames = macAppStoreAppNames
        self.macAppStoreBundleIdentifiers = macAppStoreBundleIdentifiers
        self.detectedApplications = detectedApplications
        self.externalBinaryPaths = externalBinaryPaths
        self.externalPackageInstallations = externalPackageInstallations
        self.installationIndex = installationIndex
        self.scannedAt = scannedAt
    }

    static let empty = InstallationSnapshot()
}
