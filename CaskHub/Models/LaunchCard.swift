//
//  LaunchCard.swift
//  CaskHub
//
//  Created by Ali Elsokary on 04/10/2026.
//

import Foundation

struct WhatsNewRelease {
    struct Feature {
        let symbol: String
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
    }

    let version: String
    let features: [Feature]

    static let latest = WhatsNewRelease(version: "0.10.0", features: [
        Feature(
            symbol: "spigot",
            title: .WhatsNew.feature1Title,
            detail: .WhatsNew.feature1Detail
        ),
        Feature(
            symbol: "touchid",
            title: .WhatsNew.feature2Title,
            detail: .WhatsNew.feature2Detail
        ),
        Feature(
            symbol: "pin",
            title: .WhatsNew.feature3Title,
            detail: .WhatsNew.feature3Detail
        ),
        Feature(
            symbol: "textformat",
            title: .WhatsNew.feature4Title,
            detail: .WhatsNew.feature4Detail
        )
    ])
}

enum LaunchCard: String, Identifiable {
    case welcome, whatsNew

    var id: Self { self }
}

enum LaunchCardGate {
    static let lastSeenVersionKey = "launchCardLastSeenVersion"
    static let previewKey = "launchCardPreview"

    static func resolve(
        in defaults: UserDefaults,
        currentVersion: String,
        hasPriorInstall: Bool,
        latestVersion: String
    ) -> LaunchCard? {
        switch defaults.string(forKey: previewKey) {
        case "welcome": return .welcome
        case "whatsNew": return .whatsNew
        default: break
        }

        let stored = defaults.string(forKey: lastSeenVersionKey)
        defaults.set(currentVersion, forKey: lastSeenVersionKey)
        if stored == nil, !hasPriorInstall { return .welcome }

        let isUnseen = NumericVersionComparison.compare(latestVersion, stored ?? "0") == .orderedDescending
        let isShipped = NumericVersionComparison.compare(latestVersion, currentVersion)
            .map { $0 != .orderedDescending } ?? false
        return isUnseen && isShipped ? .whatsNew : nil
    }
}
