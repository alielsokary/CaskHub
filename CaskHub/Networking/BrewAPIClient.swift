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

final class BrewAPIClient: BrewAPIClientProtocol {
    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    convenience init() {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.init(networkService: NetworkService(decoder: decoder))
    }

    func fetchAllCasks() async throws -> [Cask] {
        try await networkService.fetch(route: .allCasks)
    }

    func fetchAnalytics(period: AnalyticsPeriod) async throws -> CaskAnalyticsResponse {
        try await networkService.fetch(route: .analytics(period))
    }
}
