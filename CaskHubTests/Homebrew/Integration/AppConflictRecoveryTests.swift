//
//  AppConflictRecoveryTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 20/09/2026.
//  Copyright © 2026 BuildingLink. All rights reserved.
//

@testable import CaskHub
import AppKit
import Synchronization
import XCTest

@MainActor
final class AppConflictRecoveryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func test_conflict_recovery_intents_explain_unverified_ownership_without_running_brew() async throws {
        for button in [0, 1] {
            let runner = StubBrewProcessRunner()
            let service = makeService(runner: runner)
            let cask = makeCask("unverified", appNames: ["Unknown.app"])
            let original = conflictFailure()
            service.operationStore.send(.fail(original), for: cask.token)
            service.send(button == 0 ? .requestAdoption(cask) : .requestReplacementAdoption(cask))

            let explained = expectation(for: NSPredicate { _, _ in
                MainActor.assumeIsolated {
                    service.operationStore.state(for: cask.token)?.failure?.kind == .adoptionPreflight
                }
            }, evaluatedWith: nil)
            await fulfillment(of: [explained], timeout: 3)
            let failure = try XCTUnwrap(service.operationStore.state(for: cask.token)?.failure)
            XCTAssertTrue(failure.message.contains("verify"))
            XCTAssertTrue(failure.recoveries.isEmpty)
            XCTAssertTrue(runner.requests.isEmpty)
        }
    }

    func test_registered_identity_recovers_using_the_original_cask() async throws {
        _ = try makeApplicationBundle(in: root, named: "Known.app", bundleIdentifier: "org.example.known")
        let runner = StubBrewProcessRunner()
        let service = makeService(runner: runner)
        let original = makeCask("known", appNames: ["Known.app"])
        await service.updatePackageCatalog([original])
        await service.requestAdoption(original)
        XCTAssertEqual(service.operationStore.state(for: original.token)?.failure?.kind, .adoptionPreflight)

        var enriched = original
        enriched.catalogBundleIdentifiers = ["org.example.known"]
        await service.updatePackageCatalog([enriched])
        await service.requestAdoption(original)
        let request = try XCTUnwrap(service.operationStore.state(for: original.token)?.adoptionRequest)
        XCTAssertTrue(runner.requests.isEmpty)
        try await service.confirmAdoption(request)
        XCTAssertEqual(runner.requests.map(\.arguments), [["install", "--cask", "known", "--adopt"]])
    }

    func test_hybrid_cask_uses_verified_app_plan_and_permission_target() async throws {
        for (installed, flag) in [("1.0", "--force"), ("2.0", "--adopt"), ("3.0", "--force")] {
            let bundle = try makeApplicationBundle(
                in: root, named: "Hybrid.app", bundleIdentifier: "org.example.hybrid"
            )
            try setApplicationVersion(installed, at: bundle)
            let runner = StubBrewProcessRunner()
            let service = makeService(runner: runner)
            let cask = hybridCask()
            await service.updatePackageCatalog([cask])
            addHelperReceipt(to: service, for: cask)
            let probed = Mutex<URL?>(nil)
            service.permissionProbe = { target in
                probed.withLock { $0 = target }
                return AppManagementPermission.Assessment(status: .granted, evidence: .target)
            }

            await service.requestAdoption(cask)

            let request = try XCTUnwrap(service.operationStore.state(for: cask.token)?.adoptionRequest)
            XCTAssertEqual(request.plan.artifact, .applicationBundle)
            XCTAssertTrue(request.plan.confirmationMessage(for: cask).contains("installer"))
            XCTAssertEqual(probed.withLock { $0?.path }, bundle.path)
            XCTAssertTrue(runner.requests.isEmpty)
            try await service.confirmAdoption(request)
            XCTAssertEqual(runner.requests.map(\.arguments), [["install", "--cask", cask.token, flag]])
        }
    }

    func test_hybrid_receipts_cannot_authorize_an_unverified_or_store_app() async throws {
        for scenario in ["missing-id", "wrong-id", "store"] {
            _ = try makeApplicationBundle(
                in: root, named: "Hybrid.app",
                bundleIdentifier: scenario == "wrong-id" ? "org.example.unrelated" : "org.example.hybrid",
                macAppStoreReceipt: scenario == "store"
            )
            let runner = StubBrewProcessRunner()
            let service = makeService(runner: runner)
            var cask = hybridCask()
            if scenario == "missing-id" { cask.catalogBundleIdentifiers = nil }
            await service.updatePackageCatalog([cask])
            addHelperReceipt(to: service, for: cask)

            await service.requestAdoption(cask)
            XCTAssertEqual(service.operationStore.state(for: cask.token)?.failure?.kind, .adoptionPreflight, scenario)
            await service.requestReplacementAdoption(cask)
            XCTAssertEqual(service.operationStore.state(for: cask.token)?.failure?.kind, .adoptionPreflight, scenario)
            XCTAssertTrue(runner.requests.isEmpty, scenario)
        }
    }

    func test_hybrid_adoption_rechecks_other_destinations_before_replacement() async throws {
        let system = root.appendingPathComponent("system")
        let user = root.appendingPathComponent("user")
        let bundle = try makeApplicationBundle(in: user, named: "Hybrid.app", bundleIdentifier: "org.example.hybrid")
        try setApplicationVersion("1.0", at: bundle)
        let runner = StubBrewProcessRunner()
        let service = makeService(runner: runner, applicationDirectories: [system, user])
        let cask = hybridCask()
        await service.updatePackageCatalog([cask])
        addHelperReceipt(to: service, for: cask)
        await service.requestAdoption(cask)
        let request = try XCTUnwrap(service.operationStore.state(for: cask.token)?.adoptionRequest)
        XCTAssertEqual(request.plan.execution, .replaceApplication)
        let other = try makeApplicationBundle(in: system, named: "Hybrid.app", bundleIdentifier: "org.example.unrelated")

        try await service.confirmAdoption(request)

        XCTAssertEqual(service.operationStore.state(for: cask.token)?.failure?.kind, .adoptionPreflight)
        await service.requestAdoption(cask)
        XCTAssertEqual(service.operationStore.state(for: cask.token)?.failure?.kind, .adoptionPreflight)
        try FileManager.default.removeItem(at: other.appendingPathComponent("Contents/Info.plist"))
        await service.requestReplacementAdoption(cask)
        XCTAssertEqual(service.operationStore.state(for: cask.token)?.failure?.kind, .adoptionPreflight)
        XCTAssertTrue(runner.requests.isEmpty)
    }

    func test_dependency_conflict_does_not_offer_recovery_against_parent() async throws {
        let service = makeService(runner: StubBrewProcessRunner())
        for (token, parentApp, dependencyApp) in [
            ("pieces", "Pieces.app", "Pieces OS.app"),
            ("libreoffice-language-pack", "", "LibreOffice.app"),
            ("fs-uae-emulator", "FS-UAE.app", "FS-UAE Launcher.app")
        ] {
            let cask = makeCask(token, appNames: parentApp.isEmpty ? [] : [parentApp])
            for prefix in ["", "Error: ", "Error: \(token): "] {
                let path = "/Applications/\(dependencyApp)"
                let failure = CaskOperationFailureFactory.make(
                    from: LocalHomebrewError.brewCommandFailed(
                        args: ["install", "--cask", token, "--force"], exitCode: 1,
                        stderr: "\(prefix)It seems there is already an App at '\(path)'."
                    ), strandedCopyExists: false
                )
                let (alert, actions) = CaskActionAlertFactory.errorAlert(for: cask, failure: failure, service: service)
                XCTAssertEqual(failure.conflictingApplication?.path, path)
                XCTAssertEqual(alert.buttons.map(\.title), ["OK"])
                XCTAssertEqual(actions.count, 1)
                XCTAssertTrue(alert.informativeText.contains(dependencyApp))
                XCTAssertTrue(alert.informativeText.contains("separately"))
            }
        }
        XCTAssertNil(LocalHomebrewError.conflictingApplication(
            stderr: "Warning: It seems there is already an App at '/Applications/X.app'; overwriting."
        ))
    }

    func test_unrecognized_conflict_path_never_offers_parent_replacement() {
        let service = makeService(runner: StubBrewProcessRunner())
        let cask = makeCask("parent", appNames: ["Parent.app"])
        let failure = CaskOperationFailureFactory.make(
            from: LocalHomebrewError.brewCommandFailed(
                args: ["install", "--cask", cask.token], exitCode: 1,
                stderr: "It seems there is already an App at an unknown destination."
            ), strandedCopyExists: false
        )
        let (alert, _) = CaskActionAlertFactory.errorAlert(for: cask, failure: failure, service: service)
        XCTAssertNil(failure.conflictingApplication)
        XCTAssertEqual(alert.buttons.map(\.title), ["OK"])
        XCTAssertTrue(alert.informativeText.contains("couldn't identify"))
    }

    func test_conflict_recovery_requires_the_exact_verified_app_path() async throws {
        let bundle = try makeApplicationBundle(in: root, named: "Known.app", bundleIdentifier: "org.example.known")
        let runner = StubBrewProcessRunner()
        let service = makeService(runner: runner)
        var cask = makeCask("known", appNames: ["Known.app"])
        cask.catalogBundleIdentifiers = ["org.example.known"]
        await service.updatePackageCatalog([cask])
        for path in [bundle.path, "/Other/Applications/Known.app"] {
            let failure = CaskOperationFailureFactory.make(
                from: LocalHomebrewError.brewCommandFailed(
                    args: ["install", "--cask", cask.token], exitCode: 1,
                    stderr: "Error: It seems there is already an App at '\(path)'."
                ), strandedCopyExists: false
            )
            let (alert, _) = CaskActionAlertFactory.errorAlert(for: cask, failure: failure, service: service)
            XCTAssertEqual(alert.buttons.count, path == bundle.path ? 3 : 1)
            if path != bundle.path { XCTAssertTrue(alert.informativeText.contains("couldn't verify")) }
        }
        XCTAssertTrue(runner.requests.isEmpty)
    }

    func test_permission_resume_explains_lost_identity_without_installing() async throws {
        _ = try makeApplicationBundle(in: root, named: "Known.app", bundleIdentifier: "org.example.known")
        let runner = StubBrewProcessRunner()
        let service = makeService(runner: runner)
        var cask = makeCask("known", appNames: ["Known.app"])
        cask.catalogBundleIdentifiers = ["org.example.known"]
        await service.updatePackageCatalog([cask])
        service.permissionProbe = { _ in AppManagementPermission.Assessment(status: .denied, evidence: .target) }
        await service.requestAdoption(cask)
        XCTAssertNotNil(service.operationStore.pendingPermissions[cask.token])
        cask.catalogBundleIdentifiers = nil
        await service.updatePackageCatalog([cask])

        await service.resumePendingAdoptions()

        XCTAssertEqual(service.operationStore.state(for: cask.token)?.failure?.kind, .adoptionPreflight)
        XCTAssertTrue(runner.requests.isEmpty)
    }

    private func makeService(
        runner: StubBrewProcessRunner, applicationDirectories: [URL]? = nil
    ) -> LocalHomebrewService {
        let defaults = makeScratchDefaults("app-conflict-\(UUID().uuidString)")
        defaults.set(root.path, forKey: HomebrewLocator.customPrefixKey)
        let service = LocalHomebrewService(defaults: defaults) {
            $0.applicationDirectories = applicationDirectories ?? [root]
            $0.processRunner = runner
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
        }
        service.permissionProbe = { _ in AppManagementPermission.Assessment(status: .granted, evidence: .target) }
        return service
    }

    private func hybridCask() -> Cask {
        var cask = makeCask("hybrid", version: "2.0", appNames: ["Hybrid.app"],
                            packageIdentifiers: ["org.example.helper"])
        cask.catalogBundleIdentifiers = ["org.example.hybrid"]
        return cask
    }

    private func addHelperReceipt(to service: LocalHomebrewService, for cask: Cask) {
        let registration = InstallationCatalogBuilder().build([cask])
        let packages = PackageReceiptResolver().resolve(
            signatures: registration.packageSignatures,
            receipts: ["org.example.helper": .init(files: "Applications/Hybrid.app", location: nil)],
            availableAppNames: ["Hybrid.app"], applications: [], homebrewInstalledTokens: []
        )
        updateInstallationSnapshot(of: service) {
            $0.externalPackageInstallations = packages
            $0.externalPackageApplicationOwners[cask.token] = makeDetectedApplication("Helper.app", version: "99.0")
        }
        XCTAssertNotNil(service.installationSnapshot.externalPackageInstallations[cask.token])
    }

    private func conflictFailure() -> CaskOperationFailure {
        CaskOperationFailureFactory.make(from: LocalHomebrewError.brewCommandFailed(
            args: ["install"], exitCode: 1, stderr: "Error: It seems there is already an App at '/Applications/Unknown.app'."
        ), strandedCopyExists: false)
    }
}
