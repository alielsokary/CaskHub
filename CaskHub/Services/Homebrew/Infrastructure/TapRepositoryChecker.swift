//
//  TapRepositoryChecker.swift
//  CaskHub
//
//  Created by Ali Elsokary on 12/11/2026.
//

import Foundation

/// Asks the Git server whether the repository `brew tap` would clone exists, without needing git installed.
nonisolated struct TapRepositoryChecker: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    @concurrent
    func availability(of url: URL) async -> TapAvailability {
        var request = URLRequest(url: Self.probeURL(for: url), timeoutInterval: 8)
        // GitLab stalls requests with the default CFNetwork user agent.
        request.setValue("CaskHub", forHTTPHeaderField: "User-Agent")
        // Headers are enough; the advertised refs are never read.
        guard let (_, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse
        else { return .unreachable }
        return Self.availability(forStatusCode: http.statusCode)
    }

    /// Git's smart-HTTP ref advertisement: 200 for a public repository on any host, 401 when missing or private.
    static func probeURL(for repository: URL) -> URL {
        var base = repository.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        if !base.hasSuffix(".git") { base += ".git" }
        return URL(string: base + "/info/refs?service=git-upload-pack") ?? repository
    }

    static func availability(forStatusCode statusCode: Int) -> TapAvailability {
        switch statusCode {
        case 200 ..< 300: .available
        case 401, 403, 404: .missing
        default: .unreachable
        }
    }
}
