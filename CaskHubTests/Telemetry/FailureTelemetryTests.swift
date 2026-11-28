//
//  FailureTelemetryTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 16/11/2026.
//

@testable import CaskHub
import XCTest

extension AnalyticsTests {
    func test_homebrew_update_failure_has_its_own_action() {
        Analytics.caskActionFailed(
            .updatingHomebrew,
            token: "gimp",
            origin: .repair,
            failureKind: .unknown
        )

        XCTAssertEqual(lastSignal?.name, "Cask.actionFailed")
        XCTAssertEqual(lastSignal?.parameters, [
            "action": "updateHomebrew",
            "cask": "gimp",
            "failureClass": "unknown",
            "origin": "repair"
        ])
    }

    @MainActor
    func test_invariant_conflict_reports_context_and_failed_span() async {
        let crashSpy = await runFailingService(
            output: "Error: gimp: Cask 'gimp' conflicts with 'gimp-beta'."
        )

        XCTAssertEqual(lastSignal?.name, "Cask.actionFailed")
        XCTAssertEqual(lastSignal?.parameters["failureClass"], "cask-conflict")
        XCTAssertEqual(crashSpy.capturedErrors.count, 1)
        XCTAssertEqual(crashSpy.capturedErrorTags, [[
            "brew.action": "installing",
            "brew.cask": "gimp",
            "brew.origin": "individual"
        ]])
        XCTAssertNotNil(crashSpy.spans.last?.span.finishedError)
    }

    @MainActor
    func test_external_network_failure_is_metric_only_with_failed_span() async {
        let crashSpy = await runFailingService(
            output: "curl: (6) Could not resolve host: example.com"
        )

        XCTAssertEqual(lastSignal?.name, "Cask.actionFailed")
        XCTAssertEqual(lastSignal?.parameters["failureClass"], "network-failure")
        XCTAssertTrue(crashSpy.capturedErrors.isEmpty)
        XCTAssertNotNil(crashSpy.spans.last?.span.finishedError)
    }

    @MainActor
    func test_external_homebrew_update_failure_remains_metric_only() async {
        let crashSpy = await runFailingService(
            output: "curl: (6) Could not resolve host: example.com",
            operation: .updatingHomebrew
        )

        XCTAssertEqual(lastSignal?.parameters["action"], "updateHomebrew")
        XCTAssertEqual(lastSignal?.parameters["failureClass"], "network-failure")
        XCTAssertTrue(crashSpy.capturedErrors.isEmpty)
        XCTAssertNotNil(crashSpy.spans.last?.span.finishedError)
    }

    @MainActor
    func test_only_proven_askpass_cancellation_is_suppressed() async {
        let cancelled = await runFailingService(
            output: "sudo: no password was provided",
            markAskpassCancelled: true
        )
        XCTAssertEqual(lastSignal?.parameters["failureClass"], "sudo-declined")
        XCTAssertTrue(cancelled.capturedErrors.isEmpty)

        let failedHelper = await runFailingService(
            output: "sudo: no password was provided"
        )
        XCTAssertEqual(lastSignal?.parameters["failureClass"], "askpass-unavailable")
        XCTAssertEqual(failedHelper.capturedErrors.count, 1)
    }

    @MainActor
    func test_ambiguous_password_and_disk_image_failures_are_reported() async {
        let wrongPassword = await runFailingService(output: "sudo: 3 incorrect password attempts")
        XCTAssertEqual(lastSignal?.parameters["failureClass"], "sudo-wrong-password")
        XCTAssertEqual(wrongPassword.capturedErrors.count, 1)
        let diskImage = await runFailingService(output: "hdiutil: attach canceled")
        XCTAssertEqual(lastSignal?.parameters["failureClass"], "dmg-mount-cancelled")
        XCTAssertEqual(diskImage.capturedErrors.count, 1)
    }

    @MainActor
    func test_brew_disk_full_is_reported() async {
        let crashSpy = await runFailingService(
            output: "Error: Could not write download to /tmp/x.zip.incomplete\n"
                + "curl: (23) Failure writing output to destination, passed 16384 returned 0"
        )

        XCTAssertEqual(lastSignal?.parameters["failureClass"], "storage-full")
        XCTAssertEqual(crashSpy.capturedErrors.count, 1)
    }

    @MainActor
    func test_checksum_mismatch_and_outdated_homebrew_are_reported() async {
        let checksum = await runFailingService(
            output: "Error: SHA256 mismatch\nExpected: 0123\n  Actual: 4567\n"
        )
        XCTAssertEqual(lastSignal?.parameters["failureClass"], "checksum-mismatch")
        XCTAssertEqual(checksum.capturedErrors.count, 1)

        let runtime = await runFailingService(
            output: "Error: Cask 'gimp' definition is invalid: invalid 'command_wrapper' stanza: "
                + "Unknown key: :executable. Valid keys are: :target, :content"
        )
        XCTAssertEqual(lastSignal?.parameters["failureClass"], "homebrew-runtime-incompatible")
        XCTAssertEqual(runtime.capturedErrors.count, 1)
    }

    @MainActor
    func test_askpass_disk_full_is_reported() async {
        let crashSpy = await runFailingService(
            output: "",
            askpassError: .fileSystem(
                stage: .script,
                failureKind: .storageFull
            )
        )

        XCTAssertEqual(lastSignal?.parameters["failureClass"], "storage-full")
        XCTAssertEqual(crashSpy.capturedErrors.count, 1)
        XCTAssertNotNil(crashSpy.spans.last?.span.finishedError)
    }

    @MainActor
    func test_permission_denial_after_adoption_gate_reports_invariant_context() async {
        let crashSpy = await runFailingService(
            output: "CaskHub does not have App Management permissions",
            operation: .adopting
        )

        XCTAssertEqual(lastSignal?.parameters["failureClass"], "permission-denied")
        XCTAssertEqual(crashSpy.capturedErrorTags, [[
            "brew.action": "adopting",
            "brew.adoption_execution": "adopt-application",
            "brew.adoption_relationship": "same",
            "brew.cask": "gimp",
            "brew.origin": "individual",
            "brew.permission_evidence": "target"
        ]])
    }

    @MainActor
    func test_arm_machine_with_intel_brew_runtime_reports_architecture_invariant() async throws {
        try XCTSkipUnless(HomebrewLocator.isAppleSilicon)
        let crashSpy = await runFailingService(output: """
        This cask depends on hardware architecture being one of \
        [{type: :arm, bits: 64}], but you are running {type: :intel, bits: 64}.
        """)

        XCTAssertEqual(
            lastSignal?.parameters["failureClass"],
            "brew-architecture-mismatch"
        )
        XCTAssertEqual(crashSpy.capturedErrors.count, 1)
    }

    @MainActor
    func test_missing_app_open_reports_the_local_state_contradiction() {
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("missing-app-telemetry")
        ) {
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
        }

        service.open(makeCask("ghost", appNames: ["Ghost.app"]))

        XCTAssertEqual(lastSignal?.parameters["failureClass"], "app-bundle-not-found")
        XCTAssertEqual(crashSpy.capturedErrorTags, [[
            "brew.action": "opening",
            "brew.cask": "ghost",
            "brew.origin": "individual",
            "app.source": "external",
            "app.bundle_names": "Ghost.app"
        ]])
    }

    func test_sudo_password_mistakes_belong_to_the_user_and_policy_to_the_device() {
        XCTAssertEqual(HomebrewFailureKind.sudoWrongPassword.issueType, "User.SudoWrongPassword")
        XCTAssertEqual(HomebrewFailureKind.sudoDeclined.issueType, "User.SudoDeclined")
        XCTAssertEqual(HomebrewFailureKind.sudoNotAdmin.issueType, "Device.SudoNotAdmin")
        XCTAssertEqual(HomebrewFailureKind.sudoPolicyDenied.issueType, "Device.SudoPolicyDenied")
    }

    @MainActor
    private func runFailingService(
        output: String,
        operation: CaskAction = .installing,
        markAskpassCancelled: Bool = false,
        askpassError: AskpassScriptError? = nil
    ) async -> SpyCrashReporterProvider {
        crashSpy.capturedErrors.removeAll()
        crashSpy.capturedErrorTags.removeAll()
        crashSpy.spans.removeAll()
        CrashReporter.captureCounts = [:]

        let runner = StubBrewProcessRunner()
        let failure = BrewProcessResult(exitCode: 1, output: output)
        runner.queuedResults = operation == .updatingHomebrew || operation == .adopting ? [failure] : [.success, failure]
        let askpass = FileManager.default.temporaryDirectory
            .appendingPathComponent("caskhub-analytics-\(UUID().uuidString)")
        if markAskpassCancelled {
            runner.onRequest = { _ in
                try Data().write(to: AskpassScriptManager.cancellationMarker(
                    for: askpass
                ))
            }
        }
        let defaults = makeScratchDefaults("failure-telemetry-\(UUID().uuidString)")
        let service = LocalHomebrewService(defaults: defaults) {
            $0.fileManager = NoFilesFileManager()
            $0.processRunner = runner
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.askpassProvider = { _ in
                if let askpassError { throw askpassError }
                return askpass
            }
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
        }
        await perform(operation, on: service)
        return crashSpy
    }

    @MainActor
    private func perform(_ operation: CaskAction, on service: LocalHomebrewService) async {
        if operation == .updatingHomebrew {
            try? await service.updateHomebrew(for: "gimp")
        } else if operation == .adopting {
            let cask = makeCask("gimp", appNames: ["Gimp.app"])
            seedExternalInstallation(of: cask, version: cask.displayVersion, in: service)
            service.permissionProbe = { _ in
                AppManagementPermission.Assessment(status: .granted, evidence: .target)
            }
            await service.requestAdoption(cask)
            if let request = service.operationStore.state(for: cask.token)?.adoptionRequest {
                try? await service.confirmAdoption(request)
            }
        } else {
            try? await service.install(token: "gimp")
        }
    }
}
