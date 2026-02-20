//
//  BrewRouter.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

enum BrewRouter {
    case allCasks
    case analytics365d

    var method: HTTPMethod {
        switch self {
        case .allCasks, .analytics365d:
            return .get
        }
    }

    var path: String {
        switch self {
        case .allCasks:
            return BrewAPIConfig.EndpointPath.allCasks
        case .analytics365d:
            return BrewAPIConfig.EndpointPath.analytics365d
        }
    }

    func asURLRequest() throws -> URLRequest {
        guard let url = URL(string: BrewAPIConfig.baseURL + path) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(
            BrewAPIConfig.Headers.contentType,
            forHTTPHeaderField: "Content-Type"
        )
        return request
    }
}
