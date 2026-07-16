//
//  CrashReporter.swift
//  CaskHub
//
//  Created by Ali Elsokary on 12/07/2026.
//

import Foundation
import Sentry

/// Handle for an in-flight trace span so call sites and tests never see
/// Sentry types.
protocol CrashSpan {
    func finish()
    func finish(error: Error)
}

/// Abstraction over the crash-reporting backend, mirroring AnalyticsProvider:
/// swapping providers means one new conforming type.
protocol CrashReporterProvider {
    /// Called once from `App.init()`, before any window exists.
    /// `enabled` reflects the stored opt-out setting.
    func start(enabled: Bool)
    /// Live opt-out flip from the Settings toggle.
    func setEnabled(_ enabled: Bool)
    func capture(_ error: Error)
    func addBreadcrumb(_ message: String, data: [String: String])
    func startSpan(name: String, operation: String) -> CrashSpan
}

/// The facade the app talks to. Owns the opt-out setting (Settings → Privacy)
/// and the per-launch capture rate limit; forwards everything else to the
/// provider. Implicitly @MainActor (module default isolation) — detached
/// tasks call it with `await`.
enum CrashReporter {
    static let enabledKey = "crashReportingEnabled"

    /// `var` so tests can inject a spy; production never reassigns it.
    static var provider: CrashReporterProvider = SentryProvider()

    /// Per-launch capture counts by error signature. Internal (not private)
    /// so tests can reset between cases.
    static var captureCounts: [String: Int] = [:]
    private static let captureLimit = 5

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func start() {
        provider.start(enabled: isEnabled)
    }

    /// Re-reads the opt-out setting; call after the Settings toggle changes.
    static func refresh() {
        provider.setEnabled(isEnabled)
    }

    /// Reports a handled error. Capped at `captureLimit` per error signature
    /// per launch so a tight failure loop (e.g. disk full on every icon
    /// write) can't burn the event quota.
    static func capture(_ error: Error) {
        guard isEnabled else { return }
        let nsError = error as NSError
        let signature = "\(type(of: error)):\(nsError.domain):\(nsError.code)"
        let count = captureCounts[signature, default: 0]
        guard count < captureLimit else { return }
        captureCounts[signature] = count + 1
        provider.capture(error)
    }

    static func breadcrumb(_ message: String, data: [String: String] = [:]) {
        guard isEnabled else { return }
        provider.addBreadcrumb(message, data: data)
    }

    static func span(name: String, operation: String) -> CrashSpan {
        guard isEnabled else { return NoOpCrashSpan() }
        return provider.startSpan(name: name, operation: operation)
    }
}

/// Inert span for the opted-out and no-DSN paths.
struct NoOpCrashSpan: CrashSpan {
    func finish() {}
    func finish(error: Error) {}
}

// MARK: - Sentry

final class SentryProvider: CrashReporterProvider {
    /// Injected at build time: Configs/Secrets.xcconfig → Info.plist → here
    /// (see Configs/Secrets.xcconfig.template). Nil on builds without the
    /// secret (fresh clones, CI) — crash reporting then stays off entirely.
    private static var dsn: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String
        return value?.isEmpty == false ? value : nil
    }

    /// Sentry has no runtime pause: opt-out closes the SDK, opt-in restarts
    /// it. `started` also gates spans so we never hand out live transactions
    /// from a closed SDK.
    private var started = false

    func start(enabled: Bool) {
        guard enabled, let dsn = Self.dsn else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            // Small user base — lower if volume grows.
            options.tracesSampleRate = 1.0
            // Release/dist come from the SDK's bundle-derived defaults;
            // environment defaults to "production".
            #if DEBUG
            options.environment = "debug"
            #endif
        }
        started = true
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start(enabled: true)
        } else {
            SentrySDK.close()
            started = false
        }
    }

    func capture(_ error: Error) {
        SentrySDK.capture(error: error)
    }

    func addBreadcrumb(_ message: String, data: [String: String]) {
        let crumb = Breadcrumb(level: .info, category: "app")
        crumb.message = message
        if !data.isEmpty { crumb.data = data }
        SentrySDK.addBreadcrumb(crumb)
    }

    func startSpan(name: String, operation: String) -> CrashSpan {
        guard started else { return NoOpCrashSpan() }
        return SentrySpanHandle(span: SentrySDK.startTransaction(name: name, operation: operation))
    }
}

private struct SentrySpanHandle: CrashSpan {
    let span: any Span

    func finish() {
        span.finish()
    }

    func finish(error: Error) {
        span.finish(status: .internalError)
    }
}
