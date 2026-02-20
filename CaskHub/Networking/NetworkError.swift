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
        case .decodingError(let detail):
            return "Failed to decode the response: \(detail)"
        case .serverError(let code):
            return "Server error (HTTP \(code))."
        case .clientError(let code):
            return "Client error (HTTP \(code))."
        case .notFound:
            return "The requested resource was not found."
        case .noInternet:
            return "No internet connection. Please check your network."
        case .unknownError(let detail):
            return "An unexpected error occurred: \(detail)"
        }
    }
}
