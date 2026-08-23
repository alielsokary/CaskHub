//
//  AppHangReportingTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 13/08/2026.
//

@testable import CaskHub
import AppKit
@_spi(Private) import Sentry
import XCTest

extension CrashReporterTests {
    func test_start_passes_crash_and_analytics_consent_to_provider() {
        CrashReporter.defaults.set(false, forKey: CrashReporter.enabledKey)
        CrashReporter.start()
        XCTAssertEqual(spy.startedWith, [SentryConsent(
            crashReporting: false,
            analytics: true
        )])
    }

    func test_refresh_covers_all_consent_combinations() {
        let consents = [
            SentryConsent(crashReporting: true, analytics: true),
            SentryConsent(crashReporting: true, analytics: false),
            SentryConsent(crashReporting: false, analytics: true),
            SentryConsent(crashReporting: false, analytics: false)
        ]

        for consent in consents {
            CrashReporter.defaults.set(
                consent.crashReporting,
                forKey: CrashReporter.enabledKey
            )
            Analytics.defaults.set(consent.analytics, forKey: Analytics.enabledKey)
            CrashReporter.refresh()
        }

        XCTAssertEqual(spy.consentChanges, consents)
    }

    func test_sentry_options_support_metrics_without_crash_reporting() {
        let options = Options()

        SentryProvider.configure(
            options,
            consent: SentryConsent(crashReporting: false, analytics: true),
            appHangProcessor: AppHangEventProcessor()
        )

        XCTAssertTrue(options.enableMetrics)
        XCTAssertNotNil(options.beforeSendMetric)
        XCTAssertEqual(options.sampleRate?.doubleValue, 0)
        XCTAssertEqual(options.tracesSampleRate?.doubleValue, 0)
        XCTAssertFalse(options.enableCrashHandler)
        XCTAssertFalse(options.enableAutoSessionTracking)
        XCTAssertFalse(options.enableWatchdogTerminationTracking)
        XCTAssertFalse(options.enableAppHangTracking)
        XCTAssertFalse(options.enableAutoPerformanceTracing)
        XCTAssertFalse(options.enableCaptureFailedRequests)
        XCTAssertFalse(options.enableAutoBreadcrumbTracking)
        XCTAssertFalse(options.enableNetworkBreadcrumbs)
        XCTAssertFalse(options.enableSwizzling)
        XCTAssertFalse(options.sendClientReports)
    }

    func test_sentry_options_keep_metrics_ready_without_analytics_consent() {
        let options = Options()

        SentryProvider.configure(
            options,
            consent: SentryConsent(crashReporting: true, analytics: false),
            appHangProcessor: AppHangEventProcessor()
        )

        XCTAssertTrue(options.enableMetrics)
        XCTAssertTrue(options.enableCrashHandler)
        XCTAssertTrue(options.enableAutoSessionTracking)
        XCTAssertTrue(options.enableAppHangTracking)
        XCTAssertFalse(options.enableCaptureFailedRequests)
        XCTAssertEqual(options.tracesSampleRate?.doubleValue, 1)
        XCTAssertNotNil(options.beforeSend)
    }

    func test_metric_filter_strips_user_identifiers_and_honors_current_consent() throws {
        var analyticsEnabled = true
        let options = Options()
        SentryProvider.configure(
            options,
            consent: SentryConsent(crashReporting: false, analytics: true),
            appHangProcessor: AppHangEventProcessor(),
            isAnalyticsEnabled: { analyticsEnabled }
        )
        let metric = SentryMetric(
            timestamp: Date(),
            traceId: SentryId(),
            name: Analytics.metricKey,
            value: .counter(1),
            unit: nil,
            attributes: [
                "event.name": .string("View.modeChanged"),
                "user.id": .string("installation-id"),
                "user.name": .string("account-name"),
                "user.email": .string("ali@example.com")
            ]
        )

        let filtered = try XCTUnwrap(options.beforeSendMetric?(metric))
        XCTAssertEqual(filtered.attributes["event.name"], .string("View.modeChanged"))
        XCTAssertNil(filtered.attributes["user.id"])
        XCTAssertNil(filtered.attributes["user.name"])
        XCTAssertNil(filtered.attributes["user.email"])

        analyticsEnabled = false
        XCTAssertNil(options.beforeSendMetric?(metric))
    }

    func test_analytics_consent_changes_do_not_restart_sentry() {
        var options: [Options] = []
        var closeCount = 0
        let provider = SentryProvider(
            dsn: { "https://public@example.com/1" },
            startSDK: {
                let configured = Options()
                $0(configured)
                options.append(configured)
            },
            closeSDK: { closeCount += 1 }
        )

        provider.start(consent: SentryConsent(crashReporting: true, analytics: true))
        provider.setConsent(SentryConsent(crashReporting: true, analytics: false))
        provider.setConsent(SentryConsent(crashReporting: true, analytics: true))

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(options[0].enableMetrics)
        XCTAssertEqual(options[0].shutdownTimeInterval, 0)
    }

    func test_crash_consent_change_restarts_sentry_without_blocking() {
        var options: [Options] = []
        var lifecycle: [String] = []
        let provider = SentryProvider(
            dsn: { "https://public@example.com/1" },
            startSDK: {
                lifecycle.append("start")
                let configured = Options()
                $0(configured)
                options.append(configured)
            },
            closeSDK: { lifecycle.append("close") }
        )

        provider.start(consent: SentryConsent(crashReporting: true, analytics: true))
        provider.setConsent(SentryConsent(crashReporting: false, analytics: true))

        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(lifecycle, ["start", "close", "start"])
        XCTAssertTrue(options[0].enableCrashHandler)
        XCTAssertFalse(options[1].enableCrashHandler)
        XCTAssertEqual(options.map(\.shutdownTimeInterval), [0, 0])
    }

    func test_metrics_only_opt_out_closes_before_reenable() {
        var options: [Options] = []
        var lifecycle: [String] = []
        let provider = SentryProvider(
            dsn: { "https://public@example.com/1" },
            startSDK: {
                lifecycle.append("start")
                let configured = Options()
                $0(configured)
                options.append(configured)
            },
            closeSDK: { lifecycle.append("close") }
        )

        provider.start(consent: SentryConsent(crashReporting: false, analytics: true))
        provider.setConsent(SentryConsent(crashReporting: false, analytics: false))
        provider.setConsent(SentryConsent(crashReporting: false, analytics: true))

        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(lifecycle, ["start", "close", "start"])
    }

    func test_paused_scope_brackets_the_body() {
        activateHangTracking()

        let value = CrashReporter.withHangTrackingPaused { 7 }

        XCTAssertEqual(value, 7)
        XCTAssertEqual(spy.hangTrackingEvents, ["pause", "resume"])
    }

    func test_paused_scope_resumes_when_the_body_throws() {
        activateHangTracking()

        XCTAssertThrowsError(
            try CrashReporter.withHangTrackingPaused { throw URLError(.badURL) }
        )
        XCTAssertEqual(spy.hangTrackingEvents, ["pause", "resume"])
    }

    func test_nested_pauses_resume_only_after_the_final_scope() {
        activateHangTracking()

        CrashReporter.pauseHangTracking()
        CrashReporter.pauseHangTracking()
        CrashReporter.resumeHangTracking()

        XCTAssertEqual(spy.hangTrackingEvents, ["pause"])

        CrashReporter.resumeHangTracking()

        XCTAssertEqual(spy.hangTrackingEvents, ["pause", "resume"])
    }

    @MainActor
    func test_modal_closing_while_inactive_waits_for_activation_to_resume() {
        let coordinator = ApplicationTerminationCoordinator()
        coordinator.applicationDidBecomeActive(Notification(
            name: NSApplication.didBecomeActiveNotification
        ))
        spy.hangTrackingEvents.removeAll()

        CrashReporter.pauseHangTracking()
        coordinator.applicationWillResignActive(Notification(
            name: NSApplication.willResignActiveNotification
        ))
        CrashReporter.resumeHangTracking()

        XCTAssertEqual(spy.hangTrackingEvents, ["pause"])

        coordinator.applicationDidBecomeActive(Notification(
            name: NSApplication.didBecomeActiveNotification
        ))

        XCTAssertEqual(spy.hangTrackingEvents, ["pause", "resume"])
    }

    @MainActor
    func test_activation_during_a_modal_waits_for_the_modal_to_close() {
        CrashReporter.start()
        spy.hangTrackingEvents.removeAll()
        let coordinator = ApplicationTerminationCoordinator()

        CrashReporter.pauseHangTracking()
        coordinator.applicationDidBecomeActive(Notification(
            name: NSApplication.didBecomeActiveNotification
        ))

        XCTAssertTrue(spy.hangTrackingEvents.isEmpty)

        CrashReporter.resumeHangTracking()

        XCTAssertEqual(spy.hangTrackingEvents, ["resume"])
    }

    func test_start_and_reenable_synchronize_inactive_hang_tracking() {
        CrashReporter.start()

        XCTAssertEqual(spy.hangTrackingEvents, ["pause"])

        spy.hangTrackingEvents.removeAll()
        CrashReporter.defaults.set(false, forKey: CrashReporter.enabledKey)
        CrashReporter.refresh()
        CrashReporter.defaults.set(true, forKey: CrashReporter.enabledKey)
        CrashReporter.refresh()

        XCTAssertEqual(spy.hangTrackingEvents, ["pause"])
    }

    private func activateHangTracking() {
        CrashReporter.setApplicationActive(true)
        spy.hangTrackingEvents.removeAll()
    }
}

final class AppHangEventProcessorTests: XCTestCase {
    func test_non_app_hang_event_is_unchanged() {
        let processor = AppHangEventProcessor()
        let event = Event(level: .error)

        let processed = processor.process(event)

        XCTAssertTrue(processed === event)
        XCTAssertNil(event.fingerprint)
        XCTAssertNil(event.tags?["app_hang.family"])
    }

    func test_app_hangs_are_split_by_presymbolicated_framework_family() {
        let processor = AppHangEventProcessor()
        let windowServer = makeAppHangEvent(packages: [
            "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        ])
        let swiftUI = makeAppHangEvent(packages: [
            "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI"
        ])

        XCTAssertNotNil(processor.process(windowServer))
        XCTAssertNotNil(processor.process(swiftUI))
        XCTAssertEqual(windowServer.tags?["app_hang.family"], "window-server")
        XCTAssertEqual(swiftUI.tags?["app_hang.family"], "swift-ui")
        XCTAssertEqual(
            windowServer.fingerprint,
            ["{{ default }}", "app-hang", "window-server"]
        )
        XCTAssertEqual(
            swiftUI.fingerprint,
            ["{{ default }}", "app-hang", "swift-ui"]
        )
    }

    func test_youngest_app_frame_wins_over_swiftui_ancestor() {
        let processor = AppHangEventProcessor()
        let event = makeAppHangEvent(frames: [
            ("/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI", false),
            ("/Applications/CaskHub.app/Contents/MacOS/CaskHub", true)
        ])

        XCTAssertNotNil(processor.process(event))
        XCTAssertEqual(event.tags?["app_hang.family"], "app-code")
    }

    func test_sentry_queue_ping_does_not_merge_with_appkit_hangs() {
        let processor = AppHangEventProcessor()
        let event = makeAppHangEvent(packages: [
            "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",
            "/Applications/CaskHub.app/Contents/Frameworks/Sentry.framework/Sentry"
        ])

        XCTAssertNotNil(processor.process(event))
        XCTAssertEqual(event.tags?["app_hang.family"], "sentry")
    }

    func test_core_graphics_without_skylight_is_graphics() {
        let processor = AppHangEventProcessor()
        let event = makeAppHangEvent(packages: [
            "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",
            "/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics"
        ])

        XCTAssertNotNil(processor.process(event))
        XCTAssertEqual(event.tags?["app_hang.family"], "graphics")
    }

    private func makeAppHangEvent(packages: [String]) -> Event {
        makeAppHangEvent(frames: packages.map { ($0, false) })
    }

    private func makeAppHangEvent(frames: [(package: String, inApp: Bool)]) -> Event {
        let event = Event(level: .error)
        let exception = Exception(value: "App hanging", type: "App Hanging")
        exception.mechanism = Mechanism(type: "AppHang")
        exception.stacktrace = SentryStacktrace(
            frames: frames.map { package, inApp in
                let frame = Frame()
                frame.package = package
                frame.inApp = NSNumber(value: inApp)
                return frame
            },
            registers: [:]
        )
        event.exceptions = [exception]
        return event
    }
}
