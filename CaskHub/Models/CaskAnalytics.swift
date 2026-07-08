//
//  CaskAnalytics.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

enum AnalyticsPeriod: String, CaseIterable, Identifiable {
    case days30 = "30d"
    case days90 = "90d"
    case days365 = "365d"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .days30: return "30 Days"
        case .days90: return "90 Days"
        case .days365: return "Year"
        }
    }
}

struct CaskAnalyticsResponse: Codable {
    let category: String
    let totalItems: Int
    let startDate: String
    let endDate: String
    let totalCount: Int
    let items: [CaskAnalyticsItem]
}

struct CaskAnalyticsItem: Codable {
    let number: Int
    let cask: String
    let count: String
    let percent: String

    var downloadCount: Int {
        Int(count.replacingOccurrences(of: ",", with: "")) ?? 0
    }
}
