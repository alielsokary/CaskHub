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
    func setTag(_ key: String, value: String)
    func startSpan(name: String, operation: String) -> CrashSpan
}

enum CrashReporter {
    static let enabledKey = "crashReportingEnabled"

    static var provider: CrashReporterProvider = SentryProvider()

    static var captureCounts: [String: Int] = [:]
    private static let captureLimit = 5
    private static let ignoredURLErrorCodes: Set<Int> = [
        URLError.cancelled.rawValue,
        URLError.notConnectedToInternet.rawValue,
        URLError.timedOut.rawValue,
        URLError.networkConnectionLost.rawValue,
        URLError.cannotFindHost.rawValue,
        URLError.cannotConnectToHost.rawValue,
        URLError.dnsLookupFailed.rawValue
    ]

    /// Unit-test runs launch the host app — without a guard their brew failures,
    /// hangs, and transactions land in Sentry looking like production events.
    static let detectsTestRun = NSClassFromString("XCTestCase") != nil
    static var isRunningTests = detectsTestRun

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func start() {
        guard !isRunningTests else { return }
        provider.start(enabled: isEnabled)
    }

    static func refresh() {
        guard !isRunningTests else { return }
        provider.setEnabled(isEnabled)
    }

    static func capture(_ error: Error) {
        guard isEnabled, !isRunningTests else { return }
        // Task cancellation (e.g. a view disappearing mid-fetch) is not an error.
        if error is CancellationError {
            return
        }
        if let localError = error as? LocalHomebrewError, !localError.shouldReport {
            return
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, ignoredURLErrorCodes.contains(nsError.code) {
            return
        }
        // Disk full is user state — write paths degrade gracefully.
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileWriteOutOfSpace.rawValue {
            return
        }
        // Truncated CDN body only; garbage-but-complete payloads still report.
        if case let DecodingError.dataCorrupted(context) = error,
           let underlying = context.underlyingError as NSError?,
           underlying.domain == NSCocoaErrorDomain,
           underlying.code == NSPropertyListReadCorruptError,
           (underlying.userInfo[NSDebugDescriptionErrorKey] as? String)?
               .contains("Unexpected end of file") == true {
            return
        }
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

    static func tag(_ key: String, value: String) {
        guard isEnabled else { return }
        provider.setTag(key, value: value)
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
        SentrySDK.capture(error: error) { scope in
            if let fingerprint = Self.fingerprint(for: error) {
                scope.setFingerprint(fingerprint)
            }
        }
    }

    /// Groups brew failures per subcommand and failure class instead of NSError
    /// domain+code — one issue per way brew fails, so a rare destructive failure
    /// can't hide inside a busy catch-all group.
    static func fingerprint(for error: Error) -> [String]? {
        guard case let LocalHomebrewError.brewCommandFailed(args, _, stderr) = error,
              let subcommand = args.first else { return nil }
        return ["brewCommandFailed", subcommand, LocalHomebrewError.failureClass(stderr: stderr)]
    }

    func setTag(_ key: String, value: String) {
        SentrySDK.configureScope { $0.setTag(value: value, key: key) }
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
        span.setData(value: String(describing: error), key: "error")
        span.finish(status: .internalError)
    }
}
