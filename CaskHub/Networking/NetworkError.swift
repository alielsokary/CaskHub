//
//  NetworkError.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError(String)
    case serverError(statusCode: Int)
    case clientError(statusCode: Int)
    case notFound
    case noInternet
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL is invalid."
        case .noData:
            return "No data was received from the server."
        case let .decodingError(detail):
            return "Failed to decode the response: \(detail)"
        case let .serverError(code):
            return "Server error (HTTP \(code))."
        case let .clientError(code):
            return "Client error (HTTP \(code))."
        case .notFound:
            return "The requested resource was not found."
        case .noInternet:
            return "No internet connection. Please check your network."
        case let .unknownError(detail):
            return "An unexpected error occurred: \(detail)"
        }
    }
}
