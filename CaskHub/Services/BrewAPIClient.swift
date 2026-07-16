//
//  BrewAPIClient.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

protocol BrewAPIClientProtocol {
    func fetchAllCasks() async throws -> [Cask]
    func fetchAnalytics(period: AnalyticsPeriod) async throws -> CaskAnalyticsResponse
}

/// The two formulae.brew.sh endpoints the app consumes. Unlike the
/// best-effort CaskFlowReleases fetches, these throw: the catalog is the
/// app's main content, so the ViewModel surfaces `localizedDescription`
/// with a Retry button.
final class BrewAPIClient: BrewAPIClientProtocol {
    struct HTTPError: LocalizedError {
        let statusCode: Int

        var errorDescription: String? {
            "formulae.brew.sh returned HTTP \(statusCode)."
        }
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func fetchAllCasks() async throws -> [Cask] {
        try await fetch(URL(string: "https://formulae.brew.sh/api/cask.json")!)
    }

    func fetchAnalytics(period: AnalyticsPeriod) async throws -> CaskAnalyticsResponse {
        try await fetch(URL(
            string: "https://formulae.brew.sh/api/analytics/cask-install/\(period.rawValue).json"
        )!)
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw HTTPError(statusCode: http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }
}
