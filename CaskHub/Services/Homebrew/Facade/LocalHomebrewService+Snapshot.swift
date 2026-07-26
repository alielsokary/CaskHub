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
            caskroomURL: HomebrewLocator.caskroomURL(
                customPrefix: customBrewPrefix,
                fileManager: fileManager
            ),
            catalog: installationCatalog,
            applicationSignatures: applicationCaskSignatures,
            packageSignatures: packageCaskSignatures
        )
    }

    var installedCaskCount: Int {
        installationSnapshot.installedCasks.count
    }

    var installedCasks: [String: LocalCaskInstallation] {
        installationSnapshot.installedCasks
    }

    var lastRefresh: Date? {
        installationSnapshot.scannedAt
    }
}
