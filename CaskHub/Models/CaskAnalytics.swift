//
//  CaskAnalytics.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

nonisolated enum AnalyticsPeriod: String, CaseIterable, Identifiable {
    case days30 = "30d"
    case days90 = "90d"
    case days365 = "365d"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .days30: return "30 Days"
        case .days90: return "90 Days"
        case .days365: return "Year"
        }
    }
}

nonisolated struct CaskAnalyticsResponse: Decodable {
    let items: [CaskAnalyticsItem]
}

nonisolated struct CaskAnalyticsItem: Decodable {
    let cask: String
    let count: String

    var downloadCount: Int {
        Int(count.replacingOccurrences(of: ",", with: "")) ?? 0
    }
}
