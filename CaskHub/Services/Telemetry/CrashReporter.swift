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
    func pauseHangTracking()
    func resumeHangTracking()
}

extension CrashReporterProvider {
    func pauseHangTracking() {}
    func resumeHangTracking() {}
}

enum CrashReporter {
    static let enabledKey = "crashReportingEnabled"

    static var provider: CrashReporterProvider = SentryProvider()
    static var defaults = UserDefaults.standard

    static var captureCounts: [String: Int] = [:]
    static var isApplicationActive = false
    static var hangTrackingPauseDepth = 0
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
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func start() {
        guard !isRunningTests else { return }
        provider.start(enabled: isEnabled)
        if isEnabled { synchronizeHangTracking() }
    }

    static func refresh() {
        guard !isRunningTests else { return }
        provider.setEnabled(isEnabled)
        if isEnabled { synchronizeHangTracking() }
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
        let signature: String
        if let localError = error as? LocalHomebrewError,
           case let .brewCommandFailed(failure) = localError {
            signature = failure.rateLimitSignature
        } else {
            signature = "\(type(of: error)):\(nsError.domain):\(nsError.code)"
        }
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

    // Sentry's macOS tracker does not understand app activity or nested pauses.
    // Keep it enabled only while CaskHub is active and outside modal run loops.
    static func setApplicationActive(_ isActive: Bool) {
        let wasTracking = shouldTrackHangs
        isApplicationActive = isActive
        updateHangTracking(ifChangedFrom: wasTracking)
    }

    static func pauseHangTracking() {
        let wasTracking = shouldTrackHangs
        hangTrackingPauseDepth += 1
        updateHangTracking(ifChangedFrom: wasTracking)
    }

    static func resumeHangTracking() {
        guard hangTrackingPauseDepth > 0 else { return }
        let wasTracking = shouldTrackHangs
        hangTrackingPauseDepth -= 1
        updateHangTracking(ifChangedFrom: wasTracking)
    }

    static func withHangTrackingPaused<T>(_ body: () throws -> T) rethrows -> T {
        pauseHangTracking()
        defer { resumeHangTracking() }
        return try body()
    }

    private static var shouldTrackHangs: Bool {
        isApplicationActive && hangTrackingPauseDepth == 0
    }

    private static func updateHangTracking(ifChangedFrom wasTracking: Bool) {
        guard shouldTrackHangs != wasTracking else { return }
        synchronizeHangTracking()
    }

    private static func synchronizeHangTracking() {
        if shouldTrackHangs {
            provider.resumeHangTracking()
        } else {
            provider.pauseHangTracking()
        }
    }
}

struct NoOpCrashSpan: CrashSpan {
    func finish() {}
    func finish(error: Error) {}
}

// MARK: - Sentry

nonisolated enum AppHangFamily: String, Sendable {
    case appCode = "app-code"
    case sentry
    case sparkle
    case swiftUI = "swift-ui"
    case windowServer = "window-server"
    case graphics
    case appKit = "app-kit"
    case system
}

nonisolated final class AppHangEventProcessor: Sendable {
    private static let swiftUIFrameworks = ["swiftui", "attributegraph"]
    private static let graphicsFrameworks = ["coregraphics", "metal", "renderbox"]

    func process(_ event: Event) -> Event? {
        guard let exception = event.exceptions?.first(where: {
            $0.mechanism?.type == "AppHang"
        }) else {
            return event
        }

        let family = Self.family(
            for: exception.stacktrace?.frames
                ?? event.threads?.first(where: { $0.isMain?.boolValue == true })?
                    .stacktrace?.frames
                ?? []
        )
        var tags = event.tags ?? [:]
        tags["app_hang.family"] = family.rawValue
        event.tags = tags
        event.fingerprint = (event.fingerprint ?? ["{{ default }}"])
            + ["app-hang", family.rawValue]
        return event
    }

    private static func family(for frames: [Frame]) -> AppHangFamily {
        // Sentry stores native frames oldest-to-youngest. The youngest useful
        // frame describes the work that was actually blocking the main thread.
        for frame in frames.reversed() {
            if frame.inApp?.boolValue == true {
                return .appCode
            }
            guard let package = frame.package.map({
                URL(fileURLWithPath: $0).lastPathComponent.lowercased()
            }) else { continue }
            if let family = family(forPackage: package) {
                return family
            }
        }
        return .system
    }

    private static func family(forPackage package: String) -> AppHangFamily? {
        if package.contains("sentry") { return .sentry }
        if package.contains("sparkle") { return .sparkle }
        if swiftUIFrameworks.contains(where: package.contains) { return .swiftUI }
        if package == "skylight" { return .windowServer }
        if graphicsFrameworks.contains(where: package.contains) { return .graphics }
        if package == "appkit" { return .appKit }
        return nil
    }
}

final class SentryProvider: CrashReporterProvider {
    private static var dsn: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String
        return value?.isEmpty == false ? value : nil
    }

    private var started = false
    private let appHangProcessor = AppHangEventProcessor()

    func start(enabled: Bool) {
        guard enabled, let dsn = Self.dsn else { return }
        let appHangProcessor = appHangProcessor
        SentrySDK.start { options in
            options.dsn = dsn
            options.tracesSampleRate = 1.0
            options.beforeSend = appHangProcessor.process
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
            guard let localError = error as? LocalHomebrewError,
                  case let .brewCommandFailed(failure) = localError
            else { return }
            scope.setTag(value: failure.kind.rawValue, key: "brew.failure_class")
            scope.setTag(value: failure.subcommand ?? "missing", key: "brew.subcommand")
            scope.setTag(value: String(failure.exitCode), key: "brew.exit_code")
        }
    }

    /// Groups brew failures per subcommand and failure class instead of NSError
    /// domain+code — one issue per way brew fails, so a rare destructive failure
    /// can't hide inside a busy catch-all group.
    static func fingerprint(for error: Error) -> [String]? {
        guard case let LocalHomebrewError.brewCommandFailed(failure) = error else {
            return nil
        }
        return failure.stableFingerprint
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

    func pauseHangTracking() {
        SentrySDK.pauseAppHangTracking()
    }

    func resumeHangTracking() {
        SentrySDK.resumeAppHangTracking()
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
