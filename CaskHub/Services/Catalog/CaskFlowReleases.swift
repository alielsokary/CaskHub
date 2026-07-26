//
//  CaskFlowReleases.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/07/2026.
//

import Foundation

enum CaskFlowReleases {
    private static let baseURL = URL(
        string: "https://github.com/alielsokary/CaskFlow/releases/latest/download/"
    )!

    static func fetch<T: Decodable>(_: T.Type, asset: String) async -> T? {
        var request = URLRequest(url: baseURL.appendingPathComponent(asset))
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
