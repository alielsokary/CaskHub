//
//  CaskAnalytics.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

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
