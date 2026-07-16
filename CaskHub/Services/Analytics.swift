//
//  Analytics.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/07/2026.
//

import Foundation
import TelemetryDeck

/// Abstraction over the analytics backend: swapping providers means writing
/// one new conforming type — the event vocabulary (Analytics+Events.swift)
/// and its call sites never change.
protocol AnalyticsProvider {
    /// Called once from `App.init()`, before any window exists.
    /// `enabled` reflects the stored opt-out setting.
    func start(enabled: Bool)
    /// Live opt-out flip from the Settings toggle.
    func setEnabled(_ enabled: Bool)
    func send(_ signalName: String, parameters: [String: String])
}

/// The facade the app talks to. Owns the opt-out setting (Settings → Privacy)
/// and forwards everything else to the provider.
enum Analytics {
    static let enabledKey = "analyticsEnabled"

    /// `var` so tests can inject a spy; production never reassigns it.
    static var provider: AnalyticsProvider = TelemetryDeckProvider()

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

    static func send(_ signalName: String, parameters: [String: String] = [:]) {
        // Usage events double as pre-crash breadcrumbs. Governed by the
        // crash-reporting consent, not the analytics one — breadcrumbs only
        // leave the machine attached to a Sentry event.
        CrashReporter.breadcrumb(signalName, data: parameters)
        provider.send(signalName, parameters: parameters)
    }
}

// MARK: - TelemetryDeck

/// Session signals (launches, active users) are sent by the SDK automatically.
final class TelemetryDeckProvider: AnalyticsProvider {
    /// Injected at build time: Configs/Secrets.xcconfig → Info.plist → here
    /// (see Configs/Secrets.xcconfig.template). Nil on builds without the
    /// secret (fresh clones, CI) — analytics then stays off entirely.
    private static var appID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String
        return value?.isEmpty == false ? value : nil
    }

    /// Config is a reference type the SDK reads at send time, so keeping it
    /// lets `setEnabled` flip opt-out at runtime without re-initializing.
    private var config: TelemetryDeck.Config?

    func start(enabled: Bool) {
        guard let appID = Self.appID else { return }
        let config = TelemetryDeck.Config(appID: appID)
        config.analyticsDisabled = !enabled
        TelemetryDeck.initialize(config: config)
        self.config = config
    }

    func setEnabled(_ enabled: Bool) {
        config?.analyticsDisabled = !enabled
    }

    func send(_ signalName: String, parameters: [String: String]) {
        TelemetryDeck.signal(signalName, parameters: parameters)
    }
}
