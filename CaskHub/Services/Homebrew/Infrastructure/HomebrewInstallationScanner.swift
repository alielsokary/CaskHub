//
//  HomebrewInstallationScanner.swift
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

nonisolated struct HomebrewInstallationScanner: InstalledSoftwareScanning {
    private let applicationDiscovery = ApplicationDiscovery()
    private let applicationOwnershipResolver = ApplicationOwnershipResolver()
    private let installationIndexBuilder = InstallationIndexBuilder()
    private let packageReceiptResolver = PackageReceiptResolver()

    private struct ScanComponents: Sendable {
        let applications: ExternalApplicationScan
        let installedCasks: [String: LocalCaskInstallation]
        let binaryPaths: [String: URL]
        let packages: [String: ExternalPackageInstallation]
    }

    init() {}

    func scan(_ request: InstalledSoftwareScanRequest) async -> InstallationSnapshot {
        // FileManager enumeration and pkgutil are synchronous. This task owns a
        // complete independent scan and returns one Sendable value to MainActor.
        return await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let applications = applicationDiscovery.scan(
                fileManager: fileManager,
                directories: request.applicationDirectories
            )
            let installedCasks = request.caskroomURL.map {
                Self.scanCaskroom(
                    at: $0,
                    fileManager: fileManager,
                    applicationDirectories: request.applicationDirectories
                )
            } ?? [:]
            let binaryPaths = Self.scanBinaryDirectories(
                fileManager: fileManager
            )
            let packages = packageReceiptResolver.scan(
                signatures: request.packageSignatures,
                availableAppNames: applications.nonStoreNames,
                homebrewInstalledTokens: Set(installedCasks.keys)
            )
            let components = ScanComponents(
                applications: applications,
                installedCasks: installedCasks,
                binaryPaths: binaryPaths,
                packages: packages
            )
            return makeSnapshot(
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
            let applications = applicationDiscovery.scan(
                fileManager: fileManager,
                directories: request.applicationDirectories
            )
            let packages = request.packageSignatures.isEmpty ? [:] :
                packageReceiptResolver.scan(
                    signatures: request.packageSignatures,
                    availableAppNames: applications.nonStoreNames,
                    homebrewInstalledTokens: Set(current.installedCasks.keys)
                )
            let components = ScanComponents(
                applications: applications,
                installedCasks: current.installedCasks,
                binaryPaths: current.externalBinaryPaths,
                packages: packages
            )
            return makeSnapshot(
                request: request,
                current: current,
                components: components
            )
        }.value
    }

    private func makeSnapshot(
        request: InstalledSoftwareScanRequest,
        current: InstallationSnapshot?,
        components: ScanComponents
    ) -> InstallationSnapshot {
        let owners = applicationOwnershipResolver.resolve(
            signatures: request.applicationSignatures,
            applications: components.applications.applications,
            installedCasks: components.installedCasks
        )
        let index = installationIndexBuilder.build(
            catalog: request.catalog,
            applications: components.applications.applications,
            binaryPaths: components.binaryPaths,
            installedCasks: components.installedCasks,
            packageInstallations: components.packages
        )
        let installationDatesByToken =
            installationIndexBuilder.resolveInstallationDates(
                installedCasks: components.installedCasks,
                externalApplicationOwners: owners,
                macAppStoreApplications: index.macAppStoreApplications,
                packageInstallations: components.packages,
                applications: components.applications.applications
            )
        return InstallationSnapshot(
            installedCasks: components.installedCasks,
            applications: ApplicationInstallationSnapshot(
                externalAppNames: components.applications.adoptableNames,
                externalApplicationOwners: owners,
                macAppStoreAppNames: components.applications.macAppStoreNames,
                macAppStoreBundleIdentifiers:
                    components.applications.macAppStoreBundleIdentifiers,
                detectedApplications: components.applications.applications
            ),
            externalBinaryPaths: components.binaryPaths,
            externalPackageInstallations: components.packages,
            installationIndex: index,
            installationDatesByToken: installationDatesByToken,
            scannedAt: current?.scannedAt ?? .now
        )
    }
}

extension HomebrewInstallationScanner {
    /// A missing Caskroom is valid for fresh or absent Homebrew installations.
    static func scanCaskroom(
        fileManager: FileManager,
        applicationDirectories: [URL]? = nil
    ) -> [String: LocalCaskInstallation] {
        guard let caskroomURL = HomebrewLocator.caskroomURL(
            fileManager: fileManager
        ) else { return [:] }
        return scanCaskroom(
            at: caskroomURL,
            fileManager: fileManager,
            applicationDirectories: applicationDirectories
                ?? ApplicationDiscovery.defaultDirectories(fileManager: fileManager)
        )
    }

    static func scanCaskroom(
        at caskroomURL: URL,
        fileManager: FileManager,
        applicationDirectories: [URL]
    ) -> [String: LocalCaskInstallation] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: caskroomURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var result: [String: LocalCaskInstallation] = [:]
        for entry in entries {
            if let installation = scanCaskEntry(
                entry,
                fileManager: fileManager,
                applicationDirectories: applicationDirectories
            ) {
                result[installation.token] = installation
            }
        }
        return result
    }

    /// Filesystem truth for the stranded state: a real app directory, rather
    /// than the artifact symlink, remains inside a cask version directory.
    static func strandedCopyExists(
        in caskroomURL: URL,
        token: String,
        fileManager: FileManager
    ) -> Bool {
        let entry = caskroomURL.appendingPathComponent(token)
        guard let versionDirectories = try? fileManager.contentsOfDirectory(
            at: entry,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        for versionDirectory in versionDirectories {
            guard let items = try? fileManager.contentsOfDirectory(
                at: versionDirectory,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: []
            ) else { continue }
            for item in items where item.pathExtension == "app" {
                let isSymlink = (try? item.resourceValues(
                    forKeys: [.isSymbolicLinkKey]
                ).isSymbolicLink) == true
                var isDirectory: ObjCBool = false
                if !isSymlink,
                   fileManager.fileExists(
                       atPath: item.path,
                       isDirectory: &isDirectory
                   ),
                   isDirectory.boolValue {
                    return true
                }
            }
        }
        return false
    }

    /// Executable names in the locations used by Homebrew and common native
    /// CLI installers. GUI apps do not inherit the shell's PATH.
    static func scanBinaryDirectories(
        fileManager: FileManager,
        directories: [URL]? = nil
    ) -> [String: URL] {
        let folders = directories ?? HomebrewLocator.binaryDirectories(
            fileManager: fileManager
        )
        var paths: [String: URL] = [:]
        for folder in folders {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where fileManager.isExecutableFile(atPath: entry.path) {
                guard let values = try? entry.resourceValues(
                    forKeys: [.fileSizeKey, .isDirectoryKey]
                ),
                    values.isDirectory != true,
                    let fileSize = values.fileSize,
                    fileSize > 0
                else { continue }
                if paths[entry.lastPathComponent] == nil {
                    paths[entry.lastPathComponent] = entry
                }
            }
        }
        return paths
    }

    private static func scanCaskEntry(
        _ entry: URL,
        fileManager: FileManager,
        applicationDirectories: [URL]
    ) -> LocalCaskInstallation? {
        guard let versionDirectory = latestVersionDirectory(
            in: entry,
            fileManager: fileManager
        ) else { return nil }

        let receiptURL = entry
            .appendingPathComponent(".metadata", isDirectory: true)
            .appendingPathComponent("INSTALL_RECEIPT.json")
        let receiptExists = fileManager.fileExists(atPath: receiptURL.path)
        let receipt = receiptExists
            ? (try? Data(contentsOf: receiptURL)).flatMap {
                try? InstallReceipt(jsonData: $0)
            }
            : nil
        let isZombie = !receiptExists
            || !timestampedCaskfileExists(in: entry, fileManager: fileManager)
            || appsGoneEverywhere(
                appNames: receipt?.appBundleNames ?? [],
                versionDirectory: versionDirectory,
                fileManager: fileManager,
                applicationDirectories: applicationDirectories
            )
        let versionModifiedAt = try? versionDirectory.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        let installedAt = (try? entry.resourceValues(
            forKeys: [.creationDateKey]
        ).creationDate) ?? receipt?.lastUpdatedAt ?? versionModifiedAt

        return LocalCaskInstallation(
            token: entry.lastPathComponent,
            installedVersion: versionDirectory.lastPathComponent,
            installedAt: installedAt,
            lastUpdatedAt: receipt?.lastUpdatedAt ?? versionModifiedAt,
            appBundleNames: receipt?.appBundleNames ?? [],
            isZombie: isZombie
        )
    }

    /// Brew's installed check: newest timestamp dir must hold `Casks/<token>.rb|json`.
    private static func timestampedCaskfileExists(
        in entry: URL,
        fileManager: FileManager
    ) -> Bool {
        let metadata = entry.appendingPathComponent(".metadata", isDirectory: true)
        guard let versionDirectories = try? fileManager.contentsOfDirectory(
            at: metadata,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        let newestTimestamp = versionDirectories
            .flatMap { versionDirectory in
                (try? fileManager.contentsOfDirectory(
                    at: versionDirectory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
            }
            .max { $0.lastPathComponent < $1.lastPathComponent }
        guard let newestTimestamp else { return false }
        let token = entry.lastPathComponent
        return ["rb", "json"].contains { fileExtension in
            fileManager.fileExists(
                atPath: newestTimestamp
                    .appendingPathComponent("Casks/\(token).\(fileExtension)").path
            )
        }
    }

    private static func latestVersionDirectory(
        in entry: URL,
        fileManager: FileManager
    ) -> URL? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: entry.path,
            isDirectory: &isDirectory
        ),
            isDirectory.boolValue,
            let subdirectories = try? fileManager.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles]
            )
        else { return nil }

        let versionDirectories = subdirectories.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard let versionDirectory = versionDirectories.max(by: {
            modificationDate(of: $0) < modificationDate(of: $1)
        }) else { return nil }
        return versionDirectory
    }

    private static func appsGoneEverywhere(
        appNames: [String],
        versionDirectory: URL,
        fileManager: FileManager,
        applicationDirectories: [URL]
    ) -> Bool {
        guard !appNames.isEmpty else { return false }
        let candidateDirectories = applicationDirectories + [versionDirectory]
        return !appNames.contains { name in
            candidateDirectories.contains {
                fileManager.fileExists(
                    atPath: $0.appendingPathComponent(name).path
                )
            }
        }
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate) ?? .distantPast
    }
}
