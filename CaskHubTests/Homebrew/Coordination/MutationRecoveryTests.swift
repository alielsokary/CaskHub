//
//  MutationRecoveryTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 20/07/2026.
//

@testable import CaskHub
import AppKit
import XCTest

@MainActor
final class MutationRecoveryTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fileManager.temporaryDirectory
            .appendingPathComponent("mutation-recovery-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: root.appendingPathComponent("Caskroom/zed/1.10.3"),
            withIntermediateDirectories: true
        )
        defaults = makeScratchDefaults("repair-recovery-\(UUID().uuidString)")
        defaults.set(root.path, forKey: HomebrewLocator.customPrefixKey)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func makeService(
        runner: StubBrewProcessRunner,
        brewVersionProvider: @escaping () async -> String? = { "test" }
    ) -> LocalHomebrewService {
        LocalHomebrewService(defaults: defaults) {
            $0.fileManager = fileManager
            $0.applicationDirectories = [
                root.appendingPathComponent("Applications")
            ]
            $0.processRunner = runner
            $0.brewBinaryProvider = {
                URL(fileURLWithPath: "/test/bin/brew")
            }
            $0.brewVersionProvider = brewVersionProvider
        }
    }

    func test_repair_reinstalls_when_uninstall_returns_nonzero_after_removing_cask() async throws {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [
            BrewProcessResult(exitCode: 0, output: "fetched"),
            BrewProcessResult(exitCode: 1, output: "Error: cleanup failed\nlibxaw\nlibxmu"),
            BrewProcessResult(exitCode: 0, output: "installed")
        ]
        let caskroomEntry = root.appendingPathComponent("Caskroom/zed")
        runner.onRequest = { [fileManager, caskroomEntry] request in
            if request.arguments.first == "uninstall" {
                try fileManager.removeItem(at: caskroomEntry)
            }
        }

        try await makeService(runner: runner).repairReinstalling(token: "zed")

        XCTAssertEqual(runner.requests.map(\.arguments), [
            ["fetch", "--cask", "zed"],
            ["uninstall", "--cask", "zed", "--force"],
            ["install", "--cask", "zed"]
        ])
    }

    func test_repair_stops_when_failed_uninstall_leaves_caskroom_entry() async {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [
            BrewProcessResult(exitCode: 0, output: "fetched"),
            BrewProcessResult(exitCode: 1, output: "Error: uninstall failed")
        ]

        do {
            try await makeService(runner: runner).repairReinstalling(token: "zed")
            XCTFail("repair must stop while the broken cask entry remains")
        } catch {
            XCTAssertEqual(runner.requests.map(\.arguments), [
                ["fetch", "--cask", "zed"],
                ["uninstall", "--cask", "zed", "--force"]
            ])
        }
    }

    func test_package_replacement_stops_when_forced_uninstall_leaves_external_app() async throws {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [
            BrewProcessResult(exitCode: 0, output: "fetched"),
            BrewProcessResult(exitCode: 1, output: "Error: uninstall failed")
        ]
        let service = makeService(runner: runner)
        let applications = root.appendingPathComponent("Applications")
        let oneDrive = applications.appendingPathComponent("OneDrive.app")
        try fileManager.createDirectory(at: oneDrive, withIntermediateDirectories: true)
        updateInstallationSnapshot(of: service) {
            $0.externalPackageInstallations["onedrive"] = ExternalPackageInstallation(
                appBundleNames: ["OneDrive.app"]
            )
        }

        do {
            try await service.replacePackageForAdoption(token: "onedrive")
            XCTFail("replacement must stop while the external app remains")
        } catch {
            XCTAssertEqual(runner.requests.map(\.arguments), [
                ["fetch", "--cask", "onedrive"],
                ["uninstall", "--cask", "onedrive", "--force"]
            ])
        }
    }

    func test_package_installer_refusals_offer_staged_replacement() {
        let error = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "onedrive"],
            exitCode: 1,
            stderr: "installer: Error - A newer version of OneDrive is already installed."
        )

        let failure = CaskOperationFailureFactory.make(
            from: error,
            strandedCopyExists: false
        )

        XCTAssertEqual(failure.recoveries, [.replaceWithHomebrew])
    }

    func test_update_homebrew_runs_two_update_passes() async throws {
        let runner = StubBrewProcessRunner()
        var versionLoads = 0
        let service = makeService(runner: runner) {
            versionLoads += 1
            return versionLoads == 1 ? "old" : "new"
        }

        await service.refresh()
        XCTAssertEqual(service.brewVersion, "old")
        runner.onRequest = { request in
            if request.arguments == ["update"], runner.requests.count == 2 {
                XCTAssertEqual(
                    service.operationStore.state(for: "gimp")?.progress?.phase,
                    .performing
                )
            }
        }

        try await service.updateHomebrew(for: "gimp")

        XCTAssertEqual(runner.requests.map(\.arguments), [
            ["update"],
            ["update"]
        ])
        XCTAssertEqual(service.brewVersion, "new")
        XCTAssertEqual(versionLoads, 2)
    }

    func test_stale_homebrew_recovery_runs_through_alert_action() async {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [
            BrewProcessResult(
                exitCode: 1,
                output: "Error: Cask 'gimp' definition is invalid: invalid "
                    + "'command_wrapper' stanza: Unknown key: :executable"
            ),
            BrewProcessResult(exitCode: 0, output: "updated once"),
            BrewProcessResult(exitCode: 0, output: "updated twice")
        ]
        let versionReloaded = expectation(description: "Homebrew version reloaded")
        var versionLoads = 0
        let service = makeService(runner: runner) {
            versionLoads += 1
            if versionLoads == 2 { versionReloaded.fulfill() }
            return versionLoads == 1 ? "old" : "new"
        }
        await service.refresh()
        let cask = makeCask("gimp")

        do {
            try await service.install(cask)
            XCTFail("expected the stale Homebrew install to fail")
        } catch {}

        guard case let .failure(failure) = service.actionAlert(for: cask.token) else {
            return XCTFail("expected a recoverable command failure")
        }
        XCTAssertEqual(failure.recoveries, [.updateHomebrew])
        let (alert, actions) = CaskActionAlertFactory.errorAlert(
            for: cask,
            failure: failure,
            service: service
        )
        XCTAssertEqual(alert.buttons.map(\.title), ["Update Homebrew", "OK"])

        actions[0]()
        await fulfillment(of: [versionReloaded], timeout: 1)

        XCTAssertEqual(runner.requests.map(\.arguments), [
            ["install", "--cask", "gimp"],
            ["update"],
            ["update"]
        ])
        XCTAssertEqual(service.brewVersion, "new")
        XCTAssertNil(service.actionAlert(for: cask.token))
    }

    func test_failed_homebrew_update_keeps_a_homebrew_specific_title() async {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [BrewProcessResult(
            exitCode: 1,
            output: "Error: update failed"
        )]
        let service = makeService(runner: runner)

        do {
            try await service.updateHomebrew(for: "gimp")
            XCTFail("expected update failure")
        } catch {
            XCTAssertEqual(
                service.operationStore.state(for: "gimp")?.failure?.title,
                String(localized: "Homebrew Update Failed")
            )
        }
    }

    func test_failed_upgrade_for_uninstalled_cask_refreshes_stale_local_state() async {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [BrewProcessResult(
            exitCode: 1,
            output: "Error: Cask 'thorium' is not installed."
        )]
        let service = makeService(runner: runner)
        updateInstalledCask(installation("thorium", version: "1.0"), in: service)
        let thorium = makeCask("thorium")
        XCTAssertTrue(service.localState(for: thorium).isPresent)

        do {
            try await service.upgrade(token: "thorium")
            XCTFail("expected failure")
        } catch {}

        XCTAssertFalse(
            service.localState(for: thorium).isPresent,
            "brew disagreeing about install state must trigger a snapshot refresh"
        )
    }

    func test_brew_error_diagnostics_keep_error_before_long_cleanup_tail() async {
        let runner = StubBrewProcessRunner()
        let cleanupTail = (1...30).map { "formula-\($0)" }.joined(separator: "\n")
        runner.queuedResults = [BrewProcessResult(
            exitCode: 1,
            output: "Error: the meaningful failure\n" + cleanupTail
        )]

        do {
            try await makeService(runner: runner).install(token: "zed")
            XCTFail("expected failure")
        } catch let LocalHomebrewError.brewCommandFailed(failure) {
            XCTAssertTrue(failure.diagnostic.contains("Error: the meaningful failure"))
            XCTAssertTrue(failure.diagnostic.contains("formula-30"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
