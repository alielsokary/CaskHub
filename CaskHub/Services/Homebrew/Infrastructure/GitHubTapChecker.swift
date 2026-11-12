//
//  GitHubTapChecker.swift
//  CaskHub
//
//  Created by Ali Elsokary on 12/11/2026.
//

import Foundation

/// Asks GitHub whether the repository `brew tap` would clone exists, without needing git installed.
nonisolated struct GitHubTapChecker: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    @concurrent
    func availability(of url: URL) async -> TapAvailability {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return .unreachable }
        return Self.availability(forStatusCode: http.statusCode)
    }

    static func availability(forStatusCode statusCode: Int) -> TapAvailability {
        switch statusCode {
        case 200 ..< 400: .available
        case 404: .missing
        default: .unreachable
        }
    }
}
