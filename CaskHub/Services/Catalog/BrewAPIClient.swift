//
//  BrewAPIClient.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

nonisolated protocol BrewAPIClientProtocol {
    func fetchAllCasks() async throws -> [Cask]
    func fetchAnalytics(period: AnalyticsPeriod) async throws -> CaskAnalyticsResponse
}

nonisolated final class BrewAPIClient: BrewAPIClientProtocol {
    struct HTTPError: LocalizedError {
        let statusCode: Int

        var errorDescription: String? {
            "formulae.brew.sh returned HTTP \(statusCode)."
        }
    }

    func fetchAllCasks() async throws -> [Cask] {
        try await fetch(URL(string: "https://formulae.brew.sh/api/cask.json")!)
    }

    func fetchAnalytics(period: AnalyticsPeriod) async throws -> CaskAnalyticsResponse {
        try await fetch(URL(
            string: "https://formulae.brew.sh/api/analytics/cask-install/\(period.rawValue).json"
        )!)
    }

    // @concurrent keeps the multi-megabyte decode off the caller's actor;
    // plain nonisolated async would inherit MainActor and hang the UI.
    @concurrent private func fetch<T: Decodable & Sendable>(_ url: URL) async throws -> T {
        do {
            return try await fetchOnce(url)
        } catch let error as HTTPError where (500 ..< 600).contains(error.statusCode) {
            try await Task.sleep(for: .seconds(2))
            return try await fetchOnce(url)
        }
    }

    @concurrent private func fetchOnce<T: Decodable & Sendable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw HTTPError(statusCode: http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}
