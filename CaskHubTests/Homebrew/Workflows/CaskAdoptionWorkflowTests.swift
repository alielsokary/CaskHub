//
//  CaskAdoptionWorkflowTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 10/08/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class CaskAdoptionWorkflowTests: XCTestCase {
    func test_application_plan_executes_adopt_or_replace_from_version_relation() async throws {
        try await assertApplicationExecution(
            installedVersion: "1.0",
            homebrewVersion: "1.0",
            expectedOperation: .adopt,
            expectedArguments: ["install", "--cask", "sample", "--adopt"]
        )
        try await assertApplicationExecution(
            installedVersion: "1.0",
            homebrewVersion: "2.0",
            expectedOperation: .updateAndAdopt,
            expectedArguments: ["install", "--cask", "sample", "--force"]
        )
    }

    func test_onedrive_newer_package_executes_staged_downgrade() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner, permissionProbe: { .granted })
        let cask = makeCask(
            "onedrive",
            name: "OneDrive",
            version: "26.119.0622.0003",
            packageIdentifiers: ["com.microsoft.OneDrive"],
            packageAppNames: ["OneDrive.app"]
        )
        seedExternalInstallation(of: cask, version: "26.129.0706", in: service)

        await service.requestAdoption(cask)
        let request = try XCTUnwrap(
            service.operationStore.state(for: cask.token)?.adoptionRequest
        )
        XCTAssertEqual(request.plan.operation, .downgradeAndAdopt)
        XCTAssertEqual(request.plan.execution, .replacePackage)
        XCTAssertTrue(runner.requests.isEmpty, "confirmation must precede removal")

        try await service.confirmAdoption(request)

        XCTAssertEqual(runner.requests.map(\.arguments), [
            ["fetch", "--cask", "onedrive"],
            ["uninstall", "--cask", "onedrive", "--force"],
            ["install", "--cask", "onedrive"]
        ])
    }

    func test_same_version_package_executes_staged_replacement() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner, permissionProbe: { .granted })
        let cask = makeCask(
            "ilok-license-manager",
            name: "iLok License Manager",
            version: "6.2.0",
            packageIdentifiers: ["com.paceap.pkg.iLokLicenseManager"],
            packageAppNames: ["iLok License Manager.app"]
        )
        seedExternalInstallation(of: cask, version: "6.2.0", in: service)

        await service.requestAdoption(cask)
        let request = try XCTUnwrap(
            service.operationStore.state(for: cask.token)?.adoptionRequest
        )
        XCTAssertEqual(request.plan.operation, .adopt)
        XCTAssertEqual(request.plan.execution, .replacePackage)

        try await service.confirmAdoption(request)

        XCTAssertEqual(runner.requests.map(\.arguments), [
            ["fetch", "--cask", "ilok-license-manager"],
            ["uninstall", "--cask", "ilok-license-manager", "--force"],
            ["install", "--cask", "ilok-license-manager"]
        ])
    }

    func test_package_adoption_keeps_external_snapshot_until_install_completes() async throws {
        let runner = StubBrewProcessRunner()
        let cask = makeCask(
            "onedrive",
            name: "OneDrive",
            version: "26.119.0622.0003",
            packageIdentifiers: ["com.microsoft.OneDrive"],
            packageAppNames: ["OneDrive.app"]
        )
        let installed = LocalCaskInstallation(
            token: cask.token,
            installedVersion: cask.version,
            installedAt: nil,
            appBundleNames: ["OneDrive.app"]
        )
        let service = makeMutationService(
            runner: runner,
            scanner: FixedInstalledSoftwareScanner(snapshot: InstallationSnapshot(
                installedCasks: [cask.token: installed]
            )),
            permissionProbe: { .granted }
        )
        seedExternalInstallation(of: cask, version: "26.129.0706", in: service)
        let stableRevision = service.catalogStateRevision
        var inspectedInstallStep = false
        runner.onRequest = { request in
            guard request.arguments.first == "install" else { return }
            inspectedInstallStep = true
            XCTAssertEqual(service.catalogStateRevision, stableRevision)
            XCTAssertTrue(
                service.localState(for: cask).isAdoptable,
                "the Adopt row must remain backed by the last stable snapshot"
            )
            XCTAssertEqual(
                service.operationStore.state(for: cask.token)?.progress?.action,
                .adopting
            )
        }

        await service.requestAdoption(cask)
        let request = try XCTUnwrap(
            service.operationStore.state(for: cask.token)?.adoptionRequest
        )
        try await service.confirmAdoption(request)

        XCTAssertTrue(inspectedInstallStep)
        XCTAssertGreaterThan(service.catalogStateRevision, stableRevision)
        XCTAssertTrue(service.isInstalled(token: cask.token))
        XCTAssertFalse(service.localState(for: cask).isAdoptable)
        XCTAssertNil(service.operationStore.state(for: cask.token))
    }

    func test_package_conflict_is_blocked_before_permission_or_brew() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner, permissionProbe: { .granted })
        let cask = makeCask(
            "microsoft-office",
            packageIdentifiers: ["com.microsoft.office"],
            packageAppNames: ["Microsoft Word.app"],
            conflictingCaskTokens: ["microsoft-excel"]
        )
        seedExternalInstallation(of: cask, version: "1.0", in: service)
        updateInstalledCask(
            installation("microsoft-excel", version: "1.0"),
            in: service
        )

        await service.requestAdoption(cask)

        let failure = try XCTUnwrap(
            service.operationStore.state(for: cask.token)?.failure
        )
        XCTAssertEqual(failure.kind, .adoptionPreflight)
        XCTAssertTrue(failure.message.contains("microsoft-excel"))
        XCTAssertTrue(runner.requests.isEmpty)
    }

    private func assertApplicationExecution(
        installedVersion: String,
        homebrewVersion: String,
        expectedOperation: CaskAdoptionOperation,
        expectedArguments: [String]
    ) async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner, permissionProbe: { .granted })
        let cask = makeCask(
            "sample",
            version: homebrewVersion,
            appNames: ["Sample.app"]
        )
        seedExternalInstallation(of: cask, version: installedVersion, in: service)

        await service.requestAdoption(cask)
        let request = try XCTUnwrap(
            service.operationStore.state(for: cask.token)?.adoptionRequest
        )
        XCTAssertEqual(request.plan.operation, expectedOperation)
        try await service.confirmAdoption(request)
        XCTAssertEqual(runner.requests.map(\.arguments), [expectedArguments])
    }
}
