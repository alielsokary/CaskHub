//
//  CrashReporterTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 12/07/2026.
//

@testable import CaskHub
import XCTest

private struct CrashReporterTestState {
    let provider: CrashReporterProvider
    let defaults: UserDefaults
    let analyticsDefaults: UserDefaults
    let captureCounts: [String: Int]
    let applicationActive: Bool
    let pauseDepth: Int
    let isRunningTests: Bool
}

final class CrashReporterTests: XCTestCase {
    var spy: SpyCrashReporterProvider!
    private var originalState: CrashReporterTestState!

    override func setUp() {
        super.setUp()
        spy = SpyCrashReporterProvider()
        originalState = CrashReporterTestState(
            provider: CrashReporter.provider,
            defaults: CrashReporter.defaults,
            analyticsDefaults: Analytics.defaults,
            captureCounts: CrashReporter.captureCounts,
            applicationActive: CrashReporter.isApplicationActive,
            pauseDepth: CrashReporter.hangTrackingPauseDepth,
            isRunningTests: CrashReporter.isRunningTests
        )
        CrashReporter.provider = spy
        CrashReporter.defaults = makeScratchDefaults(
            "crash-reporter-\(ProcessInfo.processInfo.processIdentifier)"
        )
        Analytics.defaults = makeScratchDefaults(
            "crash-reporter-analytics-\(ProcessInfo.processInfo.processIdentifier)"
        )
        CrashReporter.captureCounts = [:]
        CrashReporter.isApplicationActive = false
        CrashReporter.hangTrackingPauseDepth = 0
        CrashReporter.isRunningTests = false
    }

    override func tearDown() {
        CrashReporter.provider = originalState.provider
        CrashReporter.defaults = originalState.defaults
        Analytics.defaults = originalState.analyticsDefaults
        CrashReporter.captureCounts = originalState.captureCounts
        CrashReporter.isApplicationActive = originalState.applicationActive
        CrashReporter.hangTrackingPauseDepth = originalState.pauseDepth
        CrashReporter.isRunningTests = originalState.isRunningTests
        super.tearDown()
    }

    // MARK: - Opt-out state

    func test_crash_reporting_is_enabled_by_default() {
        XCTAssertTrue(CrashReporter.isEnabled)
    }

    func test_is_enabled_reflects_stored_opt_out() {
        CrashReporter.defaults.set(false, forKey: CrashReporter.enabledKey)
        XCTAssertFalse(CrashReporter.isEnabled)
    }

    // MARK: - Capture + consent

    func test_capture_forwards_error_when_enabled() {
        CrashReporter.capture(URLError(.badServerResponse))
        XCTAssertEqual(spy.capturedErrors.count, 1)
    }

    func test_capture_is_suppressed_when_opted_out() {
        CrashReporter.defaults.set(false, forKey: CrashReporter.enabledKey)
        CrashReporter.capture(URLError(.badServerResponse))
        XCTAssertTrue(spy.capturedErrors.isEmpty)
    }

    // MARK: - Rate limiting

    func test_capture_stops_after_five_identical_errors() {
        for _ in 1...6 {
            CrashReporter.capture(URLError(.badServerResponse))
        }
        XCTAssertEqual(spy.capturedErrors.count, 5)
    }

    func test_distinct_error_signatures_are_limited_independently() {
        for _ in 1...6 {
            CrashReporter.capture(URLError(.badServerResponse))
            CrashReporter.capture(URLError(.cannotDecodeRawData))
        }
        XCTAssertEqual(spy.capturedErrors.count, 10)
    }

    func test_brew_failure_classes_are_limited_independently() {
        for _ in 1...6 {
            CrashReporter.capture(LocalHomebrewError.brewCommandFailed(
                args: ["install", "--cask", "one"],
                exitCode: 1,
                stderr: "curl: (22) The requested URL returned error: 404"
            ))
            CrashReporter.capture(LocalHomebrewError.brewCommandFailed(
                args: ["install", "--cask", "two"],
                exitCode: 1,
                stderr: "Error: two: Download failed on Cask 'two' with message: mystery"
            ))
        }

        XCTAssertEqual(spy.capturedErrors.count, 10)
    }

    func test_task_cancellation_is_never_captured() {
        CrashReporter.capture(CancellationError())
        XCTAssertTrue(spy.capturedErrors.isEmpty)
    }

    func test_transient_network_errors_are_never_captured() {
        let codes: [URLError.Code] = [
            .cancelled,
            .notConnectedToInternet,
            .timedOut,
            .networkConnectionLost,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed
        ]
        for code in codes {
            CrashReporter.capture(URLError(code))
        }
        XCTAssertTrue(spy.capturedErrors.isEmpty)
    }

    // MARK: - Test-run and environmental suppression

    func test_xctest_runs_are_detected() {
        XCTAssertTrue(CrashReporter.detectsTestRun)
    }

    func test_capture_is_suppressed_during_test_runs() {
        CrashReporter.isRunningTests = true
        CrashReporter.capture(URLError(.timedOut))
        XCTAssertTrue(spy.capturedErrors.isEmpty)
    }

    func test_start_is_inert_during_test_runs() {
        CrashReporter.isRunningTests = true
        CrashReporter.start()
        CrashReporter.refresh()
        XCTAssertTrue(spy.startedWith.isEmpty)
        XCTAssertTrue(spy.consentChanges.isEmpty)
    }

    func test_capture_does_not_guess_homebrew_operation_policy() {
        CrashReporter.capture(LocalHomebrewError.brewBinaryNotFound)
        XCTAssertEqual(spy.capturedErrors.count, 1)
    }

    func test_disk_full_and_truncated_payloads_are_never_captured() {
        func corrupt(_ debug: String) -> DecodingError {
            .dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "The given data was not valid JSON.",
                underlyingError: NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSPropertyListReadCorruptError,
                    userInfo: [NSDebugDescriptionErrorKey: debug]
                )
            ))
        }

        CrashReporter.capture(NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileWriteOutOfSpace.rawValue
        ))
        CrashReporter.capture(corrupt("Unexpected end of file during JSON parse."))
        XCTAssertTrue(spy.capturedErrors.isEmpty)

        CrashReporter.capture(DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(codingPath: [], debugDescription: "schema break")
        ))
        XCTAssertEqual(spy.capturedErrors.count, 1, "real schema breaks still report")

        CrashReporter.capture(corrupt("Invalid value around line 1, column 0."))
        XCTAssertEqual(
            spy.capturedErrors.count, 2,
            "garbage-but-complete payloads are not truncation and still report"
        )
    }

    func test_capture_does_not_apply_homebrew_operation_policy() {
        let failures = [
            "sudo: no password was provided",
            "sudo: 3 incorrect password attempts",
            "hdiutil: attach canceled"
        ]
        for stderr in failures {
            CrashReporter.capture(LocalHomebrewError.brewCommandFailed(
                args: ["install", "--cask", "x", "--adopt"],
                exitCode: 1,
                stderr: stderr
            ))
        }
        XCTAssertEqual(spy.capturedErrors.count, 3)
    }

    func test_non_user_brew_failures_reach_the_provider_when_requested() {
        CrashReporter.capture(LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "x"],
            exitCode: 1,
            stderr: "It seems there is already a Binary at '/opt/homebrew/bin/x'."
        ))
        CrashReporter.capture(LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "x"],
            exitCode: 1,
            stderr: "Error: It seems there is already an App at '/Applications/X.app'."
        ))
        CrashReporter.capture(LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "x"],
            exitCode: 1,
            stderr: "Error: x: Download failed on Cask 'x' with message: "
                + "curl: (22) The requested URL returned error: 404"
        ))
        XCTAssertEqual(spy.capturedErrors.count, 3)
    }

    // MARK: - Fingerprinting

    func test_brew_failures_fingerprint_by_subcommand_and_failure_class() {
        let stranded = LocalHomebrewError.brewCommandFailed(
            args: ["upgrade", "--cask", "tabby"], exitCode: 1,
            stderr: "Error: tabby: It seems there is already an App at "
                + "'/opt/homebrew/Caskroom/tabby/1.0.230/Tabby.app'."
        )
        XCTAssertEqual(
            SentryProvider.fingerprint(for: stranded),
            ["brewCommandFailed", "upgrade", "stranded-caskroom-app"]
        )

        let missingBinary = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "obsidian", "--adopt"], exitCode: 1,
            stderr: "Error: It seems the symlink source "
                + "'/Applications/Obsidian.app/Contents/MacOS/obsidian-cli' is not there."
        )
        XCTAssertEqual(
            SentryProvider.fingerprint(for: missingBinary),
            ["brewCommandFailed", "install", "missing-artifact-source"]
        )
    }

    private func cls(_ stderr: String) -> String {
        HomebrewCommandFailure.classify(
            arguments: [],
            exitCode: nil,
            diagnostic: stderr
        ).rawValue
    }

    func test_failure_classes_cover_observed_brew_errors() {
        XCTAssertEqual(cls("Warning: Cask 'x' is unavailable: No Cask with this name exists."), "unknown-cask")
        XCTAssertEqual(cls("Error: Cask 'sequel-ace' is not installed."), "not-installed")
        XCTAssertEqual(
            cls("chmod: /Applications/Example.app: Unable to change file mode: Operation not permitted"),
            "permission-denied"
        )
        XCTAssertEqual(
            cls("It seems the existing App is different from the one being installed."),
            "adopt-version-mismatch"
        )
        XCTAssertEqual(cls("SHA256 mismatch"), "checksum-mismatch")
        XCTAssertEqual(cls("curl: (6) Could not resolve host: example.com"), "network-failure")
        XCTAssertEqual(cls("It seems there is already a Binary at '/opt/homebrew/bin/x'."), "binary-conflict")
        XCTAssertEqual(cls("It seems there is already an App at '/Applications/X.app'."), "app-conflict")
        XCTAssertEqual(cls("sudo: no password was provided"), "sudo-declined")
        XCTAssertEqual(cls("sudo: a password is required"), "sudo-declined")
        XCTAssertEqual(
            cls("Warning: It seems there is already a Binary at '/usr/local/bin/docker'.\n"
                + "sudo: a password is required"),
            "sudo-declined",
            "a declined prompt is the terminal cause even with incidental conflict warnings"
        )
        XCTAssertEqual(cls("something novel"), "unknown")
    }

    func test_failure_classes_cover_field_mined_brew_errors() {
        XCTAssertEqual(
            cls("Sorry, try again.\nSorry, try again.\nsudo: 3 incorrect password attempts"),
            "sudo-wrong-password"
        )
        XCTAssertEqual(
            cls("user is not in the sudoers file.  This incident will be reported."),
            "sudo-not-admin"
        )
        XCTAssertEqual(
            cls("Error: tinymediamanager: Download failed on Cask 'tinymediamanager' "
                + "with message: Download failed: https://example.com/tmm.dmg\n"
                + "curl: (22) The requested URL returned error: 404"),
            "download-broken"
        )
        XCTAssertEqual(
            cls("Error: linearmouse: Download failed on Cask 'linearmouse' with message: "
                + "Download failed: https://dl.linearmouse.org/v0.11.4/LinearMouse.dmg\n"
                + "curl: (56) Recv failure: Connection reset by peer"),
            "network-failure"
        )
        XCTAssertEqual(
            cls("Error: Cannot download non-corrupt "
                + "https://formulae.brew.sh/api/internal/packages.arm64_tahoe.jws.json!"),
            "brew-api-unavailable"
        )
        XCTAssertEqual(
            cls("Error: foo: Download failed on Cask 'foo' with message: mystery"),
            "download-failed"
        )
        XCTAssertEqual(
            cls("Error: microsoft-office: Cask 'microsoft-office' conflicts with 'microsoft-excel'."),
            "cask-conflict"
        )
        XCTAssertEqual(
            cls("Error: Refusing to uninstall pieces-os\n"
                + "because it is required by pieces, which is currently installed."),
            "cask-dependency"
        )
        XCTAssertEqual(
            cls("Error: onyx: This cask does not run on macOS versions other than "
                + "Catalina, Big Sur, Monterey, Ventura, Sonoma, Sequoia and Tahoe."),
            "platform-unsupported"
        )
    }

    func test_failure_classes_cover_field_mined_brew_env_errors() {
        XCTAssertEqual(cls("Error: Another `brew update` process is already running."), "brew-busy")
        XCTAssertEqual(
            cls("Error: A `brew uninstall --cask cursor --force` process has already locked "
                + "/opt/homebrew/Cellar/llvm@21.\nPlease wait for it to finish or terminate it."),
            "brew-busy"
        )
        XCTAssertEqual(
            cls("Error: The following directories are not writable by your user:\n"
                + "/opt/homebrew/share/man/man5"),
            "homebrew-not-writable"
        )
    }

    func test_failure_classes_cover_field_mined_installer_and_env_errors() {
        XCTAssertEqual(cls("hdiutil: attach failed - Resource busy"), "dmg-mount-busy")
        XCTAssertEqual(
            cls("installer: The upgrade failed. (The Installer encountered an error.)\n"
                + "Error: Failure while executing; `/usr/bin/sudo -A -E -- "
                + "/usr/sbin/installer -pkg /private/tmp/x.pkg -target /` exited with 1."),
            "pkg-upgrade-failed"
        )
        XCTAssertEqual(
            cls("curl: (7) Failed to connect to updates.vendor.com port 443\n"
                + "installer: The install failed. (The Installer encountered an error.)\n"
                + "Error: Failure while executing; `/usr/bin/sudo -A -E -- "
                + "/usr/sbin/installer -pkg /private/tmp/vendor.pkg -target /` exited with 1."),
            "pkg-installer-failed",
            "a vendor installer's own curl chatter must not reclassify the failure"
        )
        XCTAssertEqual(
            cls("installer: Error - A newer version of OneDrive (26.129.0706) "
                + "is already installed."),
            "pkg-newer-installed"
        )
        XCTAssertEqual(
            cls("installer: Error - iLok License Manager 6.0.0 is already installed."),
            "pkg-already-installed"
        )
        XCTAssertEqual(cls("Error: Not upgrading 1 pinned package:\nmarkedit 1.33.0"), "upgrade-refused")
        XCTAssertEqual(
            cls("🍺  proton-mail was successfully upgraded!\n==> Upgraded 1 outdated package"),
            "exit-nonzero-after-success"
        )
        XCTAssertEqual(
            cls("Error: uninstall script /Applications/gpt4all/maintenancetool.app"
                + "/Contents/MacOS/maintenancetool does not exist."),
            "missing-uninstall-script"
        )
        XCTAssertEqual(
            cls("Error: Cannot change the ownership of '/Applications/Tunnelblick.app' "
                + "because your terminal does not have App Management permissions."),
            "permission-denied"
        )
    }

    func test_killed_process_with_silent_stderr_gets_its_own_class() {
        XCTAssertEqual(classify("", exitCode: 9), "process-killed")
        XCTAssertEqual(
            classify("", exitCode: 1),
            "no-diagnostic-output"
        )
        XCTAssertEqual(
            classify("Error: real failure", exitCode: 9),
            "unknown",
            "a kill with actual output classifies on the output"
        )
        let killed = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "stash"], exitCode: 9, stderr: ""
        )
        XCTAssertEqual(
            SentryProvider.fingerprint(for: killed),
            ["brewCommandFailed", "install", "process-killed"]
        )
        XCTAssertFalse(killed.isExplicitUserDecision)
    }

    private func classify(_ diagnostic: String, exitCode: Int32) -> String {
        HomebrewCommandFailure.classify(
            arguments: [],
            exitCode: exitCode,
            diagnostic: diagnostic
        ).rawValue
    }

    func test_other_errors_keep_default_grouping() {
        XCTAssertNil(SentryProvider.fingerprint(for: URLError(.timedOut)))
        XCTAssertNil(SentryProvider.fingerprint(for: LocalHomebrewError.brewBinaryNotFound))
    }

    // MARK: - Tags

    func test_tag_forwards_to_provider_when_enabled() {
        CrashReporter.tag("brew.path", value: "/opt/homebrew/bin/brew")
        XCTAssertEqual(spy.tags["brew.path"], "/opt/homebrew/bin/brew")
    }

    func test_tag_is_suppressed_when_opted_out() {
        CrashReporter.defaults.set(false, forKey: CrashReporter.enabledKey)
        CrashReporter.tag("brew.path", value: "/opt/homebrew/bin/brew")
        XCTAssertTrue(spy.tags.isEmpty)
    }

    @MainActor
    func test_homebrew_refresh_tags_the_selected_path_and_version() async {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("brew-tags")) {
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/opt/homebrew/bin/brew") }
            $0.brewVersionProvider = { "6.0.0" }
        }

        await service.refresh()

        XCTAssertEqual(spy.tags["brew.path"], "/opt/homebrew/bin/brew")
        XCTAssertEqual(spy.tags["brew.version"], "6.0.0")
    }

    // MARK: - Breadcrumbs

    func test_breadcrumb_forwards_message_and_data_when_enabled() {
        CrashReporter.breadcrumb("Cask.installed", data: ["cask": "firefox"])
        XCTAssertEqual(spy.breadcrumbs.last?.message, "Cask.installed")
        XCTAssertEqual(spy.breadcrumbs.last?.data, ["cask": "firefox"])
    }

    func test_breadcrumb_is_suppressed_when_opted_out() {
        CrashReporter.defaults.set(false, forKey: CrashReporter.enabledKey)
        CrashReporter.breadcrumb("Cask.installed")
        XCTAssertTrue(spy.breadcrumbs.isEmpty)
    }

    // MARK: - Spans

    func test_span_forwards_name_and_operation_when_enabled() {
        let span = CrashReporter.span(name: "install", operation: "brew")
        span.finish()
        XCTAssertEqual(spy.spans.last?.name, "install")
        XCTAssertEqual(spy.spans.last?.operation, "brew")
        XCTAssertEqual(spy.spans.last?.span.finished, true)
    }

    func test_span_finish_with_error_records_the_error() {
        let span = CrashReporter.span(name: "install", operation: "brew")
        span.finish(error: URLError(.timedOut))
        XCTAssertNotNil(spy.spans.last?.span.finishedError)
    }

    func test_span_is_inert_when_opted_out() {
        CrashReporter.defaults.set(false, forKey: CrashReporter.enabledKey)
        let span = CrashReporter.span(name: "install", operation: "brew")
        span.finish()
        XCTAssertTrue(spy.spans.isEmpty)
    }

    // MARK: - Hang tracking pause

    func test_sentry_provider_pause_resume_are_safe_without_started_sdk() {
        let provider = SentryProvider()
        provider.pauseHangTracking()
        provider.resumeHangTracking()
    }
}

extension CrashReporterTests {
    func test_unknown_brew_diagnostics_share_one_issue_and_use_bounded_rate_buckets() throws {
        let failures = [
            "renderer crashed before launch",
            "helper returned an impossible state",
            "catalog produced an invalid artifact",
            "installer returned an undocumented response"
        ].map {
            LocalHomebrewError.brewCommandFailed(
                args: ["install", "--cask", "example"],
                exitCode: 1,
                stderr: "Error: \($0)"
            )
        }
        let first = failures[0]
        let firstSignature = try XCTUnwrap(first.commandFailure?.rateLimitSignature)
        let second = try XCTUnwrap(failures.first {
            $0.commandFailure?.rateLimitSignature != firstSignature
        })
        XCTAssertEqual(
            SentryProvider.fingerprint(for: first),
            SentryProvider.fingerprint(for: second)
        )

        for _ in 1...6 {
            CrashReporter.capture(first)
            CrashReporter.capture(second)
        }

        XCTAssertEqual(spy.capturedErrors.count, 10)
        XCTAssertEqual(CrashReporter.captureCounts.count, 2)
    }
}
