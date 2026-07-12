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
        UserDefaults.standard.removeObject(forKey: CrashReporter.enabledKey)
    }

    override func tearDown() {
        CrashReporter.provider = originalProvider
        CrashReporter.captureCounts = [:]
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
        CrashReporter.capture(URLError(.timedOut))
        XCTAssertEqual(spy.capturedErrors.count, 1)
    }

    func test_capture_is_suppressed_when_opted_out() {
        UserDefaults.standard.set(false, forKey: CrashReporter.enabledKey)
        CrashReporter.capture(URLError(.timedOut))
        XCTAssertTrue(spy.capturedErrors.isEmpty)
    }

    // MARK: - Rate limiting

    func test_capture_stops_after_five_identical_errors() {
        for _ in 1...6 {
            CrashReporter.capture(URLError(.timedOut))
        }
        XCTAssertEqual(spy.capturedErrors.count, 5)
    }

    func test_distinct_error_signatures_are_limited_independently() {
        for _ in 1...6 {
            CrashReporter.capture(URLError(.timedOut))
            CrashReporter.capture(URLError(.notConnectedToInternet))
        }
        XCTAssertEqual(spy.capturedErrors.count, 10)
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
