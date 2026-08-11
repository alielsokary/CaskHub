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
        version: nil,
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

    private func storeApplication(
        named bundleName: String,
        bundleIdentifier: String
    ) -> DetectedApplication {
        DetectedApplication(
            url: URL(fileURLWithPath: "/Applications/\(bundleName)"),
            bundleName: bundleName,
            bundleIdentifier: bundleIdentifier,
            version: nil,
            isMacAppStore: true,
            isDirectlyInApplicationDirectory: true
        )
    }

    private func storeSignature(
        token: String,
        bundleName: String,
        hasPackage: Bool,
        applicationIdentifiers: [String] = [],
        packageIdentifiers: [String] = []
    ) -> MacAppStoreCaskSignature {
        MacAppStoreCaskSignature(
            token: token,
            bundleNames: [bundleName],
            hasPackageArtifact: hasPackage,
            applicationBundleIdentifiers: applicationIdentifiers,
            packageIdentifiers: packageIdentifiers
        )
    }

    func test_shared_app_name_resolves_to_exact_bundle_identifier_match() {
        let owners = ApplicationOwnershipResolver().resolve(
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

        let owners = ApplicationOwnershipResolver().resolve(
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
            version: nil,
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

        let owners = ApplicationOwnershipResolver().resolve(
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
            version: nil,
            isMacAppStore: false,
            isDirectlyInApplicationDirectory: true
        )
        let signature = ApplicationCaskSignature(
            token: "unique",
            appBundleNames: ["Unique.app"],
            bundleIdentifiers: []
        )

        let owners = ApplicationOwnershipResolver().resolve(
            signatures: [signature],
            applications: [application],
            installedCasks: [:]
        )

        XCTAssertEqual(owners["unique"], application)
    }

    func test_store_resolution_indexes_direct_and_bundle_family_matches() {
        let applications = [
            storeApplication(
                named: "Canva.app",
                bundleIdentifier: "com.canva.CanvaDesktop"
            ),
            storeApplication(
                named: "Tailscale.app",
                bundleIdentifier: "io.tailscale.ipn.macos"
            ),
            storeApplication(
                named: "Shade.app",
                bundleIdentifier: "com.limit-point.Shade"
            )
        ]
        let signatures = [
            storeSignature(
                token: "canva",
                bundleName: "Canva.app",
                hasPackage: false
            ),
            storeSignature(
                token: "tailscale-app",
                bundleName: "Tailscale.app",
                hasPackage: true,
                applicationIdentifiers: ["io.tailscale.ipn.macsys"],
                packageIdentifiers: ["com.tailscale.ipn.macsys"]
            ),
            storeSignature(
                token: "shade",
                bundleName: "Shade.app",
                hasPackage: true,
                packageIdentifiers: ["com.shade.shade"]
            )
        ]

        let result = InstallationIndexBuilder().resolveMacAppStoreApplications(
            signatures: signatures,
            applications: applications,
            installedCasks: [:]
        )

        XCTAssertEqual(Set(result.keys), ["canva", "tailscale-app"])
        XCTAssertEqual(result["canva"], applications[0])
        XCTAssertEqual(result["tailscale-app"], applications[1])
    }

    func test_installation_index_excludes_brew_owned_tokens_and_indexes_cli_paths() {
        let installed = LocalCaskInstallation(
            token: "store-app",
            installedVersion: "1.0",
            installedAt: nil,
            appBundleNames: ["Store.app"]
        )
        let storeApplication = DetectedApplication(
            url: URL(fileURLWithPath: "/Applications/Store.app"),
            bundleName: "Store.app",
            bundleIdentifier: "com.example.store",
            version: nil,
            isMacAppStore: true,
            isDirectlyInApplicationDirectory: true
        )
        let cliURL = URL(fileURLWithPath: "/usr/local/bin/tool")

        let index = InstallationIndexBuilder().build(
            catalog: CaskInstallationCatalog(
                tokens: ["store-app", "tool"],
                macAppStoreSignatures: [
                    storeSignature(
                        token: "store-app",
                        bundleName: "Store.app",
                        hasPackage: false
                    )
                ],
                binarySignatures: [
                    BinaryCaskSignature(token: "tool", binaryNames: ["missing", "tool"])
                ]
            ),
            applications: [storeApplication],
            binaryPaths: ["tool": cliURL],
            installedCasks: ["store-app": installed]
        )

        XCTAssertEqual(index.catalogTokens, ["store-app", "tool"])
        XCTAssertTrue(index.macAppStoreApplications.isEmpty)
        XCTAssertEqual(index.externalCLIPaths, ["tool": cliURL])
    }

    func test_homebrew_application_state_is_resolved_during_the_scan() {
        let signatures = [
            CaskApplicationSignature(
                token: "live",
                currentBundleNames: ["Live.app"],
                launchableBundleNames: ["Live.app"]
            ),
            CaskApplicationSignature(
                token: "gone",
                currentBundleNames: ["Gone.app"],
                launchableBundleNames: ["Gone.app"]
            )
        ]
        let liveApplication = DetectedApplication(
            url: URL(fileURLWithPath: "/Applications/Live.app"),
            bundleName: "Live.app",
            bundleIdentifier: "com.example.live",
            version: nil,
            isMacAppStore: false,
            isDirectlyInApplicationDirectory: true
        )
        let installed = [
            "live": LocalCaskInstallation(
                token: "live", installedVersion: "1.0", installedAt: nil,
                appBundleNames: ["Live.app"], isZombie: false
            ),
            "gone": LocalCaskInstallation(
                token: "gone", installedVersion: "1.0", installedAt: nil,
                appBundleNames: ["Gone.app"], isZombie: true
            )
        ]

        let result = InstallationIndexBuilder().resolveHomebrewApplicationState(
            signatures: signatures,
            applications: [liveApplication],
            installedCasks: installed
        )

        XCTAssertEqual(result.launchableTokens, ["live"])
        XCTAssertEqual(result.zombieTokens, ["gone"])
    }

    @MainActor
    func test_local_state_uses_precomputed_launchability_and_zombie_verdicts() {
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("precomputed-local-state")
        )
        let cask = makeCask("gone", version: "2.0", appNames: ["Gone.app"])
        updateInstallationSnapshot(of: service) {
            $0.installedCasks = [
                cask.token: LocalCaskInstallation(
                    token: cask.token,
                    installedVersion: "1.0",
                    installedAt: nil,
                    appBundleNames: ["Gone.app"],
                    isZombie: true
                )
            ]
            $0.installationIndex = CaskInstallationIndex(
                catalogTokens: [cask.token],
                macAppStoreApplications: [:],
                externalCLIPaths: [:],
                launchableHomebrewTokens: [],
                verifiedZombieTokens: [cask.token]
            )
        }

        let state = service.localState(for: cask)

        XCTAssertEqual(state.installationSource, .homebrew)
        XCTAssertEqual(state.uninstallAvailability, .available)
        XCTAssertTrue(state.isZombie)
        XCTAssertFalse(state.canOpen)
        XCTAssertFalse(state.hasAvailableUpdate)
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
            defaults: makeScratchDefaults("glaze-ownership")
        ) {
            $0.applicationDirectories = [root]
        }
        let glazeApp = makeCask("glaze-app", appNames: ["Glaze.app"])
        let raycastGlaze = makeCask(
            "raycast-glaze",
            appNames: ["Glaze.app"],
            applicationBundleIdentifiers: ["app.glaze.macos.main"]
        )

        await service.updatePackageCatalog([glazeApp, raycastGlaze])

        XCTAssertFalse(service.localState(for: glazeApp).isAdoptable)
        XCTAssertTrue(service.localState(for: raycastGlaze).isAdoptable)
        XCTAssertEqual(
            service.localState(for: raycastGlaze).installationSource,
            .externalApplication
        )
    }

    @MainActor
    func test_catalog_presence_lookup_performance() {
        let itemCount = 500
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("catalog-presence-performance")
        )
        let casks = (0..<itemCount).map { index in
            makeCask("store-\(index)", appNames: ["Store \(index).app"])
        }
        let applications = (0..<itemCount).map { index in
            storeApplication(
                named: "Store \(index).app",
                bundleIdentifier: "com.example.store\(index)"
            )
        }
        let storeSignatures = casks.map { cask in
            storeSignature(
                token: cask.token,
                bundleName: cask.appArtifactNames[0],
                hasPackage: false
            )
        }
        updateInstallationSnapshot(of: service) {
            $0.installationIndex = InstallationIndexBuilder().build(
                catalog: CaskInstallationCatalog(
                    tokens: Set(casks.map(\.token)),
                    macAppStoreSignatures: storeSignatures,
                    binarySignatures: []
                ),
                applications: applications,
                binaryPaths: [:],
                installedCasks: [:]
            )
        }

        XCTAssertTrue(service.localState(for: casks[0]).isPresent)
        XCTAssertTrue(service.localState(for: casks[itemCount - 1]).isPresent)

        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<20 {
                for cask in casks {
                    _ = service.localState(for: cask).isPresent
                }
            }
        }
    }
}
