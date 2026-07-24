//
//  ExternalApplicationOwnershipTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 24/07/2026.
//

@testable import CaskHub
import XCTest

final class ExternalApplicationOwnershipTests: XCTestCase {
    private let glaze = DetectedApplication(
        url: URL(fileURLWithPath: "/Applications/Glaze.app"),
        bundleName: "Glaze.app",
        bundleIdentifier: "app.glaze.macos.main",
        isMacAppStore: false,
        isDirectlyInApplicationDirectory: true
    )

    private let glazeSignatures = [
        ApplicationCaskSignature(
            token: "glaze-app",
            appBundleNames: ["Glaze.app"],
            bundleIdentifiers: []
        ),
        ApplicationCaskSignature(
            token: "raycast-glaze",
            appBundleNames: ["Glaze.app"],
            bundleIdentifiers: ["app.glaze.macos.main"]
        )
    ]

    func test_shared_app_name_resolves_to_exact_bundle_identifier_match() {
        let owners = LocalHomebrewService.resolveExternalApplicationOwners(
            signatures: glazeSignatures,
            applications: [glaze],
            installedCasks: [:]
        )

        XCTAssertNil(owners["glaze-app"])
        XCTAssertEqual(owners["raycast-glaze"], glaze)
    }

    func test_installed_cask_claims_shared_app_before_external_resolution() {
        let installed = LocalCaskInstallation(
            token: "raycast-glaze",
            installedVersion: "0.11.1",
            installedAt: nil,
            appBundleNames: ["Glaze.app"]
        )

        let owners = LocalHomebrewService.resolveExternalApplicationOwners(
            signatures: glazeSignatures,
            applications: [glaze],
            installedCasks: ["raycast-glaze": installed]
        )

        XCTAssertTrue(owners.isEmpty)
    }

    func test_shared_app_name_without_one_exact_identifier_match_is_not_adoptable() {
        let application = DetectedApplication(
            url: URL(fileURLWithPath: "/Applications/Shared.app"),
            bundleName: "Shared.app",
            bundleIdentifier: "com.example.shared",
            isMacAppStore: false,
            isDirectlyInApplicationDirectory: true
        )
        let signatures = [
            ApplicationCaskSignature(
                token: "shared-one",
                appBundleNames: ["Shared.app"],
                bundleIdentifiers: []
            ),
            ApplicationCaskSignature(
                token: "shared-two",
                appBundleNames: ["Shared.app"],
                bundleIdentifiers: []
            )
        ]

        let owners = LocalHomebrewService.resolveExternalApplicationOwners(
            signatures: signatures,
            applications: [application],
            installedCasks: [:]
        )

        XCTAssertTrue(owners.isEmpty)
    }

    func test_unique_app_name_remains_adoptable_without_bundle_identifier_metadata() {
        let application = DetectedApplication(
            url: URL(fileURLWithPath: "/Applications/Unique.app"),
            bundleName: "Unique.app",
            bundleIdentifier: "com.example.unique",
            isMacAppStore: false,
            isDirectlyInApplicationDirectory: true
        )
        let signature = ApplicationCaskSignature(
            token: "unique",
            appBundleNames: ["Unique.app"],
            bundleIdentifiers: []
        )

        let owners = LocalHomebrewService.resolveExternalApplicationOwners(
            signatures: [signature],
            applications: [application],
            installedCasks: [:]
        )

        XCTAssertEqual(owners["unique"], application)
    }

    @MainActor
    func test_catalog_resolution_exposes_only_raycast_glaze_for_adoption() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glaze-ownership-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApplicationBundle(
            in: root,
            named: "Glaze.app",
            bundleIdentifier: "app.glaze.macos.main"
        )
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("glaze-ownership"),
            applicationDirectories: [root]
        )
        let glazeApp = makeCask("glaze-app", appNames: ["Glaze.app"])
        let raycastGlaze = makeCask(
            "raycast-glaze",
            appNames: ["Glaze.app"],
            applicationBundleIdentifiers: ["app.glaze.macos.main"]
        )

        await service.updatePackageCatalog([glazeApp, raycastGlaze])

        XCTAssertFalse(service.isAdoptable(glazeApp))
        XCTAssertTrue(service.isAdoptable(raycastGlaze))
        XCTAssertEqual(
            service.installationSource(for: raycastGlaze),
            .externalApplication
        )
    }
}
