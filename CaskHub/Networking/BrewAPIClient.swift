//
//  BrewAPIClient.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

protocol BrewAPIClientProtocol {
    func fetchAllCasks() async throws -> [Cask]
    func fetchAnalytics() async throws -> CaskAnalyticsResponse
}

final class BrewAPIClient: BrewAPIClientProtocol {
    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return NetworkService(decoder: decoder)
    }()) {
        self.networkService = networkService
    }

    func fetchAllCasks() async throws -> [Cask] {
        try await networkService.fetch(route: .allCasks)
    }

    func fetchAnalytics() async throws -> CaskAnalyticsResponse {
        try await networkService.fetch(route: .analytics365d)
    }
}
