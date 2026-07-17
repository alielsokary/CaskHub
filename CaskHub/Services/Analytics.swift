//
//  Analytics.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/07/2026.
//

import Foundation
import TelemetryDeck

protocol AnalyticsProvider {
    func start(enabled: Bool)
    func setEnabled(_ enabled: Bool)
    func send(_ signalName: String, parameters: [String: String])
}

enum Analytics {
    static let enabledKey = "analyticsEnabled"

    static var provider: AnalyticsProvider = TelemetryDeckProvider()

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func start() {
        provider.start(enabled: isEnabled)
    }

    static func refresh() {
        provider.setEnabled(isEnabled)
    }

    static func send(_ signalName: String, parameters: [String: String] = [:]) {
        CrashReporter.breadcrumb(signalName, data: parameters)
        provider.send(signalName, parameters: parameters)
    }
}

// MARK: - TelemetryDeck

/// Session signals (launches, active users) are sent by the SDK automatically.
final class TelemetryDeckProvider: AnalyticsProvider {
    private static var appID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String
        return value?.isEmpty == false ? value : nil
    }

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
        guard config != nil else { return }
        TelemetryDeck.signal(signalName, parameters: parameters)
    }
}
