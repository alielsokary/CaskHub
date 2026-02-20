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
        static let analytics365d = "/api/analytics/cask-install/365d.json"
    }

    enum Headers {
        static let contentType = "application/json"
    }
}
