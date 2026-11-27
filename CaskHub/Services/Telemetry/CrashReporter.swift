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
    func start(consent: SentryConsent)
    func setConsent(_ consent: SentryConsent)
    func capture(_ error: Error, tags: [String: String])
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

nonisolated struct SentryConsent: Equatable, Sendable {
    let crashReporting: Bool
    let analytics: Bool

    var isEmpty: Bool { !crashReporting && !analytics }
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
        provider.start(consent: consent)
        if isEnabled { synchronizeHangTracking() }
    }

    static func refresh() {
        guard !isRunningTests else { return }
        provider.setConsent(consent)
        if isEnabled { synchronizeHangTracking() }
    }

    private static var consent: SentryConsent {
        SentryConsent(crashReporting: isEnabled, analytics: Analytics.isEnabled)
    }

    static func capture(_ error: Error, tags: [String: String] = [:]) {
        guard isEnabled, !isRunningTests else { return }
        // Task cancellation (e.g. a view disappearing mid-fetch) is not an error.
        if error is CancellationError {
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
        provider.capture(error, tags: tags)
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

final class SentryProvider: CrashReporterProvider {
    private let dsn: () -> String?
    private let startSDK: (@escaping (Options) -> Void) -> Void
    private let closeSDK: () -> Void
    private var consent: SentryConsent?
    private var started = false
    private let appHangProcessor = AppHangEventProcessor()
    init(
        dsn: @escaping () -> String? = {
            let value = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String
            return value?.isEmpty == false ? value : nil
        },
        startSDK: @escaping (@escaping (Options) -> Void) -> Void = {
            SentrySDK.start(configureOptions: $0)
        },
        closeSDK: @escaping () -> Void = SentrySDK.close
    ) {
        self.dsn = dsn
        self.startSDK = startSDK
        self.closeSDK = closeSDK
    }
    func start(consent: SentryConsent) { configure(for: consent) }
    func setConsent(_ consent: SentryConsent) { configure(for: consent) }

    private func configure(for consent: SentryConsent) {
        let previousConsent = self.consent
        guard consent != previousConsent else { return }
        self.consent = consent

        if let previousConsent,
           previousConsent.crashReporting == consent.crashReporting {
            if consent.isEmpty {
                stop()
            } else if !started {
                start(for: consent)
            }
            return
        }

        stop()
        start(for: consent)
    }

    private func start(for consent: SentryConsent) {
        guard !consent.isEmpty, let dsn = dsn() else { return }

        let appHangProcessor = appHangProcessor
        startSDK { options in
            options.dsn = dsn
            options.shutdownTimeInterval = 0
            Self.configure(
                options,
                consent: consent,
                appHangProcessor: appHangProcessor,
                isCrashReportingEnabled: { CrashReporter.isEnabled },
                isAnalyticsEnabled: { Analytics.isEnabled }
            )
            #if DEBUG
            options.environment = "debug"
            #endif
        }
        started = true
    }

    private func stop() {
        guard started else { return }
        closeSDK()
        started = false
    }

    static func configure(
        _ options: Options,
        consent: SentryConsent,
        appHangProcessor: AppHangEventProcessor,
        isCrashReportingEnabled: @escaping () -> Bool = { CrashReporter.isEnabled },
        isAnalyticsEnabled: @escaping () -> Bool = { Analytics.isEnabled }
    ) {
        options.enableMetrics = true
        // Report handled failures at app boundaries, not once per raw request attempt.
        options.enableCaptureFailedRequests = false
        options.beforeSendMetric = { metric in
            guard isAnalyticsEnabled() else { return nil }
            var metric = metric
            metric.attributes.removeValue(forKey: "user.id")
            metric.attributes.removeValue(forKey: "user.name")
            metric.attributes.removeValue(forKey: "user.email")
            return metric
        }

        guard consent.crashReporting else {
            options.sampleRate = 0
            options.tracesSampleRate = 0
            options.enableCrashHandler = false
            options.enableAutoSessionTracking = false
            options.enableWatchdogTerminationTracking = false
            options.enableAppHangTracking = false
            options.enableAutoPerformanceTracing = false
            options.enableNetworkTracking = false
            options.enableFileIOTracing = false
            options.enableCoreDataTracing = false
            options.enableAutoBreadcrumbTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableSwizzling = false
            options.sendClientReports = false
            options.beforeSend = { _ in nil }
            options.beforeSendSpan = { _ in nil }
            return
        }

        options.tracesSampleRate = 1.0
        options.beforeSend = {
            guard isCrashReportingEnabled() else { return nil }
            return appHangProcessor.process($0)
        }
        options.beforeSendSpan = {
            isCrashReportingEnabled() ? $0 : nil
        }
    }

    func capture(_ error: Error, tags: [String: String]) {
        SentrySDK.capture(error: Self.reportedError(error)) { scope in
            if let fingerprint = Self.fingerprint(for: error) {
                scope.setFingerprint(fingerprint)
            }
            for (key, value) in tags {
                scope.setTag(value: value, key: key)
            }
            if error is StrandedCopyDetected { scope.setLevel(.warning) }
            guard let localError = error as? LocalHomebrewError else { return }
            if let kind = localError.failureKind {
                scope.setTag(value: kind.rawValue, key: "brew.failure_class")
                scope.setTag(value: kind.area.rawValue, key: "brew.area")
                if kind.reportsAsWarning { scope.setLevel(.warning) }
            }
            if case let .askpassUnavailable(stage, _) = localError {
                scope.setTag(value: stage.rawValue, key: "brew.askpass_stage")
            }
            guard case let .brewCommandFailed(failure) = localError else { return }
            scope.setTag(value: failure.subcommand ?? "missing", key: "brew.subcommand")
            scope.setTag(value: String(failure.exitCode), key: "brew.exit_code")
            if let report = failure.diagnosticReport {
                scope.setTag(value: report.headline, key: "brew.diagnostic_headline")
                scope.setContext(value: ["diagnostic": report.text], key: "brew")
            }
        }
    }
    /// Names the issue `Area.Class` (e.g. `Homebrew.AppConflict`) with `<command> · <cleaned Error line>`.
    static func reportedError(_ error: Error) -> any Error {
        guard let localError = error as? LocalHomebrewError, let kind = localError.failureKind else { return error }
        let failure = localError.commandFailure
        let detail = [failure?.subcommand, failure?.normalizedHeadline]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        let userInfo = detail.isEmpty ? [:] : [NSDebugDescriptionErrorKey: detail]
        return NSError(domain: kind.issueType, code: Int(failure?.exitCode ?? 0), userInfo: userInfo)
    }

    static func fingerprint(for error: Error) -> [String]? {
        if let stranded = error as? StrandedCopyDetected {
            return [StrandedCopyDetected.errorDomain, stranded.subcommand, stranded.failureKind?.rawValue ?? "unknown"]
        }
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

    func pauseHangTracking() { SentrySDK.pauseAppHangTracking() }
    func resumeHangTracking() { SentrySDK.resumeAppHangTracking() }
}

private struct SentrySpanHandle: CrashSpan {
    let span: any Span

    func finish() { span.finish() }

    func finish(error: Error) {
        span.setData(value: String(reflecting: type(of: error)), key: "error.type")
        if case let LocalHomebrewError.brewCommandFailed(failure) = error {
            span.setData(value: failure.kind.rawValue, key: "brew.failure_class")
            span.setData(value: failure.subcommand ?? "missing", key: "brew.subcommand")
            span.setData(value: failure.exitCode, key: "brew.exit_code")
        }
        span.finish(status: .internalError)
    }
}
