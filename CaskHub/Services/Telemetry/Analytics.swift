//
//  Analytics.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/07/2026.
//

import Foundation
import Sentry
import TelemetryDeck

protocol AnalyticsProvider {
    func start(enabled: Bool)
    func setEnabled(_ enabled: Bool)
}

enum Analytics {
    static let enabledKey = "analyticsEnabled"
    static let metricKey = "caskhub.analytics.event"

    static var provider: AnalyticsProvider = TelemetryDeckProvider()
    static var metrics: SentryMetricsApiProtocol = SentrySDK.metrics
    static var defaults = UserDefaults.standard

    static var isEnabled: Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func start() {
        provider.start(enabled: isEnabled)
    }

    static func refresh() {
        provider.setEnabled(isEnabled)
        CrashReporter.refresh()
    }

    static func send(_ signalName: String, parameters: [String: String] = [:]) {
        CrashReporter.breadcrumb(signalName, data: parameters)
        guard isEnabled else { return }

        var attributes: [String: SentryAttributeValue] = [
            "event.name": signalName,
            "schema.version": 1
        ]
        for (key, value) in parameters {
            attributes["event.\(key)"] = value
        }
        metrics.count(key: metricKey, value: 1, attributes: attributes)
    }
}

// MARK: - TelemetryDeck

/// Session signals (launches, active users) are sent by the SDK automatically.
final class TelemetryDeckProvider: AnalyticsProvider {
    private let appID: () -> String?
    private let initialize: (TelemetryDeck.Config) -> Void
    private var config: TelemetryDeck.Config?

    init(
        appID: @escaping () -> String? = {
            let value = Bundle.main.object(
                forInfoDictionaryKey: "TelemetryDeckAppID"
            ) as? String
            return value?.isEmpty == false ? value : nil
        },
        initialize: @escaping (TelemetryDeck.Config) -> Void = {
            TelemetryDeck.initialize(config: $0)
        }
    ) {
        self.appID = appID
        self.initialize = initialize
    }

    func start(enabled: Bool) {
        guard let appID = appID() else { return }
        let config = TelemetryDeck.Config(appID: appID)
        config.analyticsDisabled = !enabled
        initialize(config)
        self.config = config
    }

    func setEnabled(_ enabled: Bool) {
        config?.analyticsDisabled = !enabled
    }
}
