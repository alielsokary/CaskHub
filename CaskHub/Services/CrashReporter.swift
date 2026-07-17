//
//  CrashReporter.swift
//  CaskHub
//
//  Created by Ali Elsokary on 12/07/2026.
//

import Foundation
import Sentry

protocol CrashSpan {
    func finish()
    func finish(error: Error)
}

protocol CrashReporterProvider {
    func start(enabled: Bool)
    func setEnabled(_ enabled: Bool)
    func capture(_ error: Error)
    func addBreadcrumb(_ message: String, data: [String: String])
    func startSpan(name: String, operation: String) -> CrashSpan
}

enum CrashReporter {
    static let enabledKey = "crashReportingEnabled"

    static var provider: CrashReporterProvider = SentryProvider()

    static var captureCounts: [String: Int] = [:]
    private static let captureLimit = 5

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func start() {
        provider.start(enabled: isEnabled)
    }

    static func refresh() {
        provider.setEnabled(isEnabled)
    }

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

struct NoOpCrashSpan: CrashSpan {
    func finish() {}
    func finish(error: Error) {}
}

// MARK: - Sentry

final class SentryProvider: CrashReporterProvider {
    private static var dsn: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String
        return value?.isEmpty == false ? value : nil
    }

    private var started = false

    func start(enabled: Bool) {
        guard enabled, let dsn = Self.dsn else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.tracesSampleRate = 1.0
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
