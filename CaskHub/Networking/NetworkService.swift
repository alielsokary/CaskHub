//
//  NetworkService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

protocol NetworkServiceProtocol {
    func fetch<T: Decodable>(route: BrewRouter) async throws -> T
}

final class NetworkService: NetworkServiceProtocol {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    func fetch<T: Decodable>(route: BrewRouter) async throws -> T {
        let request = try route.asURLRequest()

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Response Validation

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknownError("Invalid response type")
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            return
        case 404:
            throw NetworkError.notFound
        case 400 ... 499:
            throw NetworkError.clientError(statusCode: httpResponse.statusCode)
        case 500 ... 599:
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw NetworkError.unknownError("Unexpected HTTP status: \(httpResponse.statusCode)")
        }
    }
}
