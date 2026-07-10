//
//  CaskFlowReleases.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/07/2026.
//

import Foundation

/// Fetches data assets from CaskFlow's latest GitHub release.
enum CaskFlowReleases {
    /// GitHub redirects `releases/latest/download/<asset>` to the newest
    /// release's asset, so these URLs are stable across releases.
    private static let baseURL = URL(
        string: "https://github.com/alielsokary/CaskFlow/releases/latest/download/"
    )!

    /// Best-effort fetch and decode of a release asset. Returns nil on any
    /// network, HTTP, or decoding failure — callers keep their current data.
    static func fetch<T: Decodable>(_: T.Type, asset: String) async -> T? {
        var request = URLRequest(url: baseURL.appendingPathComponent(asset))
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
