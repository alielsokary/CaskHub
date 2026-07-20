//
//  CrashReporterTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 12/07/2026.
//

@testable import CaskHub
import XCTest

final class CrashReporterTests: XCTestCase {
    private var spy: SpyCrashReporterProvider!
    private var originalProvider: CrashReporterProvider!

    override func setUp() {
        super.setUp()
        spy = SpyCrashReporterProvider()
        originalProvider = CrashReporter.provider
        CrashReporter.provider = spy
        CrashReporter.captureCounts = [:]
        CrashReporter.isRunningTests = false
        UserDefaults.standard.removeObject(forKey: CrashReporter.enabledKey)
    }

    override func tearDown() {
        CrashReporter.provider = originalProvider
        CrashReporter.captureCounts = [:]
        CrashReporter.isRunningTests = CrashReporter.detectsTestRun
        UserDefaults.standard.removeObject(forKey: CrashReporter.enabledKey)
        super.tearDown()
    }

    // MARK: - Opt-out state

    func test_crash_reporting_is_enabled_by_default() {
        XCTAssertTrue(CrashReporter.isEnabled)
    }

    func test_is_enabled_reflects_stored_opt_out() {
        UserDefaults.standard.set(false, forKey: CrashReporter.enabledKey)
        XCTAssertFalse(CrashReporter.isEnabled)
    }

    func test_start_passes_stored_setting_to_provider() {
        UserDefaults.standard.set(false, forKey: CrashReporter.enabledKey)
        CrashReporter.start()
        XCTAssertEqual(spy.startedWith, [false])
    }

    func test_refresh_forwards_current_setting_to_provider() {
        UserDefaults.standard.set(false, forKey: CrashReporter.enabledKey)
        CrashReporter.refresh()
        UserDefaults.standard.set(true, forKey: CrashReporter.enabledKey)
        CrashReporter.refresh()
        XCTAssertEqual(spy.enabledChanges, [false, true])
    }

    // MARK: - Capture + consent

    func test_capture_forwards_error_when_enabled() {
        CrashReporter.capture(URLError(.badServerResponse))
        XCTAssertEqual(spy.capturedErrors.count, 1)
    }

    func test_capture_is_suppressed_when_opted_out() {
        UserDefaults.standard.set(false, forKey: CrashReporter.enabledKey)
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

    func test_transient_network_errors_are_never_captured() {
        let codes: [URLError.Code] = [
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
        XCTAssertTrue(spy.enabledChanges.isEmpty)
    }

    func test_environmental_errors_are_never_captured() {
        CrashReporter.capture(LocalHomebrewError.brewBinaryNotFound)
        XCTAssertTrue(spy.capturedErrors.isEmpty)
    }

    func test_recoverable_brew_failures_are_never_captured() {
        let failures = [
            "It seems the existing App is different from the one being installed.",
            "Error: zed: It seems there is already an App at "
                + "'/opt/homebrew/Caskroom/zed/1.10.3/Zed.app'.",
            "chmod: /Applications/Example.app/Contents/MacOS/example: Operation not permitted",
            "SHA256 mismatch",
            "Download failed: curl: (6) Could not resolve host: example.com"
        ]
        for stderr in failures {
            CrashReporter.capture(LocalHomebrewError.brewCommandFailed(
                args: ["install", "--cask", "x", "--adopt"],
                exitCode: 1,
                stderr: stderr
            ))
        }
        XCTAssertTrue(spy.capturedErrors.isEmpty)
    }

    func test_unexpected_brew_conflicts_remain_reportable() {
        CrashReporter.capture(LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "x"],
            exitCode: 1,
            stderr: "It seems there is already a Binary at '/opt/homebrew/bin/x'."
        ))
        XCTAssertEqual(spy.capturedErrors.count, 1)
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

    func test_failure_classes_cover_observed_brew_errors() {
        func cls(_ stderr: String) -> String {
            LocalHomebrewError.failureClass(stderr: stderr)
        }
        XCTAssertEqual(cls("Warning: Cask 'x' is unavailable: No Cask with this name exists."), "unknown-cask")
        XCTAssertEqual(cls("Error: Cask 'sequel-ace' is not installed."), "not-installed")
        XCTAssertEqual(
            cls("chmod: /Applications/Example.app: Unable to change file mode: Operation not permitted"),
            "permission-denied"
        )
        XCTAssertEqual(cls("It seems the existing App is different from the one being installed."), "adopt-version-mismatch")
        XCTAssertEqual(cls("SHA256 mismatch"), "checksum-mismatch")
        XCTAssertEqual(cls("curl: (6) Could not resolve host: example.com"), "network-failure")
        XCTAssertEqual(cls("It seems there is already a Binary at '/opt/homebrew/bin/x'."), "binary-conflict")
        XCTAssertEqual(cls("It seems there is already an App at '/Applications/X.app'."), "app-conflict")
        XCTAssertEqual(cls("something novel"), "uncategorized")
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
        UserDefaults.standard.set(false, forKey: CrashReporter.enabledKey)
        CrashReporter.tag("brew.path", value: "/opt/homebrew/bin/brew")
        XCTAssertTrue(spy.tags.isEmpty)
    }

    // MARK: - Breadcrumbs

    func test_breadcrumb_forwards_message_and_data_when_enabled() {
        CrashReporter.breadcrumb("Cask.installed", data: ["cask": "firefox"])
        XCTAssertEqual(spy.breadcrumbs.last?.message, "Cask.installed")
        XCTAssertEqual(spy.breadcrumbs.last?.data, ["cask": "firefox"])
    }

    func test_breadcrumb_is_suppressed_when_opted_out() {
        UserDefaults.standard.set(false, forKey: CrashReporter.enabledKey)
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
        UserDefaults.standard.set(false, forKey: CrashReporter.enabledKey)
        let span = CrashReporter.span(name: "install", operation: "brew")
        span.finish()
        XCTAssertTrue(spy.spans.isEmpty)
    }
}
