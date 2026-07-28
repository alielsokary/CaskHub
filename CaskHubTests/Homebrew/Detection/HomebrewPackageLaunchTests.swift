//
//  HomebrewPackageLaunchTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 29/07/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class HomebrewPackageLaunchTests: XCTestCase {
    private struct SUT {
        let variantApp: URL
        let cask: Cask
        let launcher: RecordingApplicationLauncher
        let service: LocalHomebrewService
    }

    func test_homebrew_owned_cask_opens_variant_named_package_payload() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("homebrew-package-variant-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sut = try makeSUT(in: root)

        XCTAssertTrue(sut.service.localState(for: sut.cask).canOpen)

        sut.service.open(sut.cask)
        XCTAssertEqual(
            sut.launcher.lastOpenedURL?.standardizedFileURL,
            sut.variantApp.standardizedFileURL
        )
    }

    private func makeSUT(in root: URL) throws -> SUT {
        let variantApp = try makeInstalledApplicationBundle(in: root)
        let applications = ApplicationDiscovery()
            .scan(fileManager: .default, directories: [root])
            .applications
        let cask = makeCask(
            "example-app", name: "Example App",
            packageIdentifiers: ["com.example.pkg.app"],
            packageAppNames: ["Example App.app"]
        )
        let registration = InstallationCatalogBuilder().build([cask])
        let installed = LocalCaskInstallation(
            token: cask.token,
            installedVersion: "2.0",
            installedAt: nil,
            appBundleNames: []
        )
        let packages = packageInstallations(
            registration: registration,
            token: cask.token
        )
        let index = InstallationIndexBuilder().build(
            catalog: registration.installationCatalog,
            applications: applications,
            binaryPaths: [:],
            installedCasks: [cask.token: installed],
            packageInstallations: packages
        )
        let launcher = RecordingApplicationLauncher()
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("homebrew-package-variant")
        ) {
            $0.applicationDirectories = [root]
            $0.applicationLauncher = launcher
        }
        updateInstallationSnapshot(of: service) {
            $0.installedCasks = [cask.token: installed]
            $0.detectedApplications = applications
            $0.externalPackageInstallations = packages
            $0.installationIndex = index
        }
        return SUT(
            variantApp: variantApp,
            cask: cask,
            launcher: launcher,
            service: service
        )
    }

    private func makeInstalledApplicationBundle(in root: URL) throws -> URL {
        try makeApplicationBundle(
            in: root,
            named: "Example App Beta.app",
            bundleIdentifier: "com.example.app.beta"
        )
    }

    private func packageInstallations(
        registration: InstallationCatalogRegistration,
        token: String
    ) -> [String: ExternalPackageInstallation] {
        PackageReceiptResolver().resolve(
            signatures: registration.packageSignatures,
            installedReceipts: ["com.example.pkg.app"],
            packageFileLists: [
                "com.example.pkg.app": "Applications/Example App Beta.app"
            ],
            availableAppNames: ["Example App Beta.app"],
            homebrewInstalledTokens: [token]
        )
    }
}
