//
//  BrewAPIConfig.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

enum BrewAPIConfig {
    static let baseURL = "https://formulae.brew.sh"

    enum EndpointPath {
        static let allCasks = "/api/cask.json"

        static func analytics(_ period: AnalyticsPeriod) -> String {
            "/api/analytics/cask-install/\(period.rawValue).json"
        }
    }

    enum Headers {
        static let contentType = "application/json"
    }
}
