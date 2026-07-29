//
//  InstallationSnapshot.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated struct ApplicationInstallationSnapshot: Sendable {
    let externalAppNames: Set<String>
    let externalApplicationOwners: [String: DetectedApplication]
    let macAppStoreAppNames: Set<String>
    let macAppStoreBundleIdentifiers: [String: Set<String>]
    let detectedApplications: [DetectedApplication]

    init(
        externalAppNames: Set<String> = [],
        externalApplicationOwners: [String: DetectedApplication] = [:],
        macAppStoreAppNames: Set<String> = [],
        macAppStoreBundleIdentifiers: [String: Set<String>] = [:],
        detectedApplications: [DetectedApplication] = []
    ) {
        self.externalAppNames = externalAppNames
        self.externalApplicationOwners = externalApplicationOwners
        self.macAppStoreAppNames = macAppStoreAppNames
        self.macAppStoreBundleIdentifiers = macAppStoreBundleIdentifiers
        self.detectedApplications = detectedApplications
    }

    static let empty = ApplicationInstallationSnapshot()
}

nonisolated struct InstallationSnapshot: Sendable {
    let installedCasks: [String: LocalCaskInstallation]
    let applications: ApplicationInstallationSnapshot
    let externalBinaryPaths: [String: URL]
    let externalPackageInstallations: [String: ExternalPackageInstallation]
    let installationIndex: CaskInstallationIndex
    let installationDatesByToken: [String: CaskInstallationDates]
    let scannedAt: Date?

    var externalAppNames: Set<String> {
        applications.externalAppNames
    }

    var externalApplicationOwners: [String: DetectedApplication] {
        applications.externalApplicationOwners
    }

    var macAppStoreAppNames: Set<String> {
        applications.macAppStoreAppNames
    }

    var macAppStoreBundleIdentifiers: [String: Set<String>] {
        applications.macAppStoreBundleIdentifiers
    }

    var detectedApplications: [DetectedApplication] {
        applications.detectedApplications
    }

    init(
        installedCasks: [String: LocalCaskInstallation] = [:],
        applications: ApplicationInstallationSnapshot = .empty,
        externalBinaryPaths: [String: URL] = [:],
        externalPackageInstallations: [String: ExternalPackageInstallation] = [:],
        installationIndex: CaskInstallationIndex = .empty,
        installationDatesByToken: [String: CaskInstallationDates] = [:],
        scannedAt: Date? = nil
    ) {
        self.installedCasks = installedCasks
        self.applications = applications
        self.externalBinaryPaths = externalBinaryPaths
        self.externalPackageInstallations = externalPackageInstallations
        self.installationIndex = installationIndex
        self.installationDatesByToken = installationDatesByToken
        self.scannedAt = scannedAt
    }

    static let empty = InstallationSnapshot()
}
