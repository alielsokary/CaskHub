//
//  CaskAdoptionWorkflowTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 10/08/2026.
//

@testable import CaskHub
import Synchronization
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
        let scanner = MutableInstalledSoftwareScanner()
        let service = makeMutationService(
            runner: runner,
            scanner: scanner,
            permissionProbe: { .granted }
        )
        seedExternalInstallation(of: cask, version: "26.129.0706", in: service)
        var sequenceRevision: Int?
        var inspectedInstallStep = false
        runner.onRequest = { request in
            if sequenceRevision == nil { sequenceRevision = service.catalogStateRevision }
            guard request.arguments.first == "install" else { return }
            inspectedInstallStep = true
            XCTAssertEqual(service.catalogStateRevision, sequenceRevision)
            XCTAssertTrue(
                service.localState(for: cask).isAdoptable,
                "the Adopt row must remain backed by the last stable snapshot"
            )
            XCTAssertEqual(
                service.operationStore.state(for: cask.token)?.progress?.action,
                .adopting
            )
            scanner.replace(with: InstallationSnapshot(
                installedCasks: [cask.token: installed]
            ))
        }

        await service.requestAdoption(cask)
        let request = try XCTUnwrap(
            service.operationStore.state(for: cask.token)?.adoptionRequest
        )
        try await service.confirmAdoption(request)

        XCTAssertTrue(inspectedInstallStep)
        XCTAssertGreaterThan(service.catalogStateRevision, sequenceRevision ?? 0)
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

extension CaskAdoptionWorkflowTests {
    func test_adoption_permission_probe_receives_exact_detected_target_bundle() async throws {
        let appsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("adoption-permission-\(UUID().uuidString)")
        let appURL = try makeApplicationBundle(
            in: appsDirectory, named: "Target.app", bundleIdentifier: "com.example.target"
        )
        defer { try? FileManager.default.removeItem(at: appsDirectory) }
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("adoption-permission-target")
        ) {
            $0.applicationDirectories = [appsDirectory]
        }
        let probedTarget = Mutex<URL?>(nil)
        service.permissionProbe = { target in
            probedTarget.withLock { $0 = target }
            return AppManagementPermission.Assessment(status: .granted, evidence: .target)
        }
        let cask = makeCask("target", appNames: ["Target.app"])
        seedExternalInstallation(of: cask, version: "1.0", url: appURL, in: service)

        await service.requestAdoption(cask)

        XCTAssertEqual(probedTarget.withLock { $0 }, appURL)
        XCTAssertNotNil(service.operationStore.state(for: cask.token)?.adoptionRequest)
    }

    func test_package_permission_probe_prefers_scanner_owned_bundle() async {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner)
        let cask = makeCask(
            "package-owner",
            packageIdentifiers: ["com.example.package-owner"],
            packageAppNames: ["Catalog Name.app"]
        )
        let owner = makeDetectedApplication(
            "Actual Package.app",
            id: "com.example.actual-package",
            version: cask.displayVersion
        )
        updateInstallationSnapshot(of: service) {
            $0.externalPackageInstallations[cask.token] = ExternalPackageInstallation(
                appBundleNames: [owner.bundleName]
            )
            $0.externalPackageApplicationOwners[cask.token] = owner
        }
        let probedTarget = Mutex<URL?>(nil)
        service.permissionProbe = { target in
            probedTarget.withLock { $0 = target }
            return AppManagementPermission.Assessment(status: .granted, evidence: .target)
        }

        await service.requestAdoption(cask)

        XCTAssertEqual(probedTarget.withLock { $0 }, owner.url)
    }

    func test_unprobeable_target_can_continue_after_returning_from_settings() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner)
        service.permissionProbe = { _ in
            AppManagementPermission.Assessment(status: .unknown, evidence: nil)
        }
        let cask = makeCask("unprobeable", appNames: ["Unprobeable.app"])
        seedExternalInstallation(of: cask, version: cask.displayVersion, in: service)

        await service.requestAdoption(cask)
        XCTAssertNotNil(service.operationStore.pendingPermissions[cask.token])

        await service.resumePendingAdoptions()
        let request = try XCTUnwrap(
            service.operationStore.state(for: cask.token)?.adoptionRequest
        )
        try await service.confirmAdoption(request)

        XCTAssertEqual(runner.requests.map(\.arguments), [[
            "install", "--cask", cask.token, "--adopt"
        ]])
    }

    func test_confirmation_replans_from_fresh_installation_snapshot() async throws {
        let runner = StubBrewProcessRunner()
        let cask = makeCask(
            "replanned-package",
            packageIdentifiers: ["com.example.replanned"],
            packageAppNames: ["Replanned.app"]
        )
        let refreshedApplication = makeDetectedApplication(
            "Replanned.app", version: "999.0"
        )
        let scanner = FixedInstalledSoftwareScanner(snapshot: InstallationSnapshot(
            applications: ApplicationInstallationSnapshot(
                externalPackageApplicationOwners: [cask.token: refreshedApplication],
                detectedApplications: [refreshedApplication]
            ),
            externalPackageInstallations: [
                cask.token: ExternalPackageInstallation(
                    appBundleNames: [refreshedApplication.bundleName]
                )
            ]
        ))
        let service = makeMutationService(
            runner: runner,
            scanner: scanner,
            permissionProbe: { .granted }
        )
        seedExternalInstallation(of: cask, version: cask.displayVersion, in: service)
        await service.requestAdoption(cask)
        let original = try XCTUnwrap(
            service.operationStore.state(for: cask.token)?.adoptionRequest
        )

        try await service.confirmAdoption(original)

        let updated = try XCTUnwrap(
            service.operationStore.state(for: cask.token)?.adoptionRequest
        )
        XCTAssertNotEqual(updated, original)
        XCTAssertEqual(updated.plan.operation, .downgradeAndAdopt)
        XCTAssertEqual(updated.plan.execution, .replacePackage)
        XCTAssertTrue(runner.requests.isEmpty)
    }

    func test_confirmation_stops_when_fresh_snapshot_no_longer_has_the_app() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(
            runner: runner,
            scanner: FixedInstalledSoftwareScanner(snapshot: .empty),
            permissionProbe: { .granted }
        )
        let cask = makeCask("removed", appNames: ["Removed.app"])
        seedExternalInstallation(of: cask, version: cask.displayVersion, in: service)
        await service.requestAdoption(cask)
        let request = try XCTUnwrap(
            service.operationStore.state(for: cask.token)?.adoptionRequest
        )

        try await service.confirmAdoption(request)

        XCTAssertNil(service.operationStore.state(for: cask.token))
        XCTAssertTrue(runner.requests.isEmpty)
    }

    func test_replacement_recovery_still_handles_external_executable() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner, permissionProbe: { .granted })
        let cask = makeCask("binary-only", binaryNames: ["binary-only"])
        updateInstallationSnapshot(of: service) {
            $0.externalBinaryPaths[cask.token] = URL(fileURLWithPath: "/usr/local/bin/binary-only")
        }

        await service.requestReplacementAdoption(cask)
        let request = try XCTUnwrap(
            service.operationStore.state(for: cask.token)?.adoptionRequest
        )
        XCTAssertEqual(request.intent, .replacement)
        XCTAssertEqual(request.plan.execution, .replaceApplication)

        try await service.confirmAdoption(request)

        XCTAssertEqual(runner.requests.map(\.arguments), [[
            "install", "--cask", cask.token, "--force"
        ]])
    }
}
