//
//  InstallationDateIndexTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 29/07/2026.
//

@testable import CaskHub
import XCTest

final class InstallationDateIndexTests: XCTestCase {
    func test_index_uses_the_resolved_non_store_package_application() {
        let homebrewInstalledAt = Date(timeIntervalSince1970: 100)
        let storeCreatedAt = Date(timeIntervalSince1970: 200)
        let packageCreatedAt = Date(timeIntervalSince1970: 300)
        let storeApplication = DetectedApplication(
            url: URL(fileURLWithPath: "/Applications/Shared.app"),
            bundleName: "Shared.app",
            bundleIdentifier: "com.example.store",
            isMacAppStore: true,
            isDirectlyInApplicationDirectory: true,
            installedAt: storeCreatedAt
        )
        let packageApplication = DetectedApplication(
            url: URL(fileURLWithPath: "/Applications/Direct/Shared.app"),
            bundleName: "Shared.app",
            bundleIdentifier: "com.example.direct",
            isMacAppStore: false,
            isDirectlyInApplicationDirectory: false,
            installedAt: packageCreatedAt
        )

        let dates = InstallationIndexBuilder().resolveInstallationDates(
            installedCasks: [
                "managed": LocalCaskInstallation(
                    token: "managed",
                    installedVersion: "1.0",
                    installedAt: homebrewInstalledAt,
                    appBundleNames: []
                )
            ],
            externalApplicationOwners: [:],
            macAppStoreApplications: ["store": storeApplication],
            packageInstallations: [
                "package": ExternalPackageInstallation(
                    appBundleNames: ["Shared.app"]
                )
            ],
            applications: [storeApplication, packageApplication]
        )

        XCTAssertEqual(dates["managed"]?.installedAt, homebrewInstalledAt)
        XCTAssertEqual(dates["managed"]?.basis, .homebrewMetadata)
        XCTAssertEqual(dates["store"]?.installedAt, storeCreatedAt)
        XCTAssertEqual(dates["store"]?.basis, .applicationBundleAttributes)
        XCTAssertEqual(dates["package"]?.installedAt, packageCreatedAt)
        XCTAssertEqual(dates["package"]?.basis, .applicationBundleAttributes)
    }
}
