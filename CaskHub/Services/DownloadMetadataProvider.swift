//
//  DownloadMetadataProvider.swift
//  CaskHub
//

import Foundation

nonisolated enum DownloadSizeResult: Equatable, Sendable {
    case known(Int64)
    case unknown
}

nonisolated protocol DownloadMetadataProviding: Sendable {
    func downloadSize(for urlString: String?) async -> DownloadSizeResult
}

actor DownloadMetadataProvider: DownloadMetadataProviding {
    typealias ContentLengthLoader = @Sendable (URL) async -> Int64?

    static let shared = DownloadMetadataProvider()

    private var cache: [String: DownloadSizeResult] = [:]
    private let contentLengthLoader: ContentLengthLoader

    init(contentLengthLoader: ContentLengthLoader? = nil) {
        self.contentLengthLoader = contentLengthLoader ?? Self.loadContentLength
    }

    func downloadSize(for urlString: String?) async -> DownloadSizeResult {
        guard let urlString, let url = URL(string: urlString) else {
            return .unknown
        }
        if let cached = cache[urlString] {
            return cached
        }

        let result = await contentLengthLoader(url).map(DownloadSizeResult.known)
            ?? .unknown
        cache[urlString] = result
        return result
    }

    private nonisolated static func loadContentLength(from url: URL) async -> Int64? {
        var head = URLRequest(url: url, timeoutInterval: 15)
        head.httpMethod = "HEAD"
        if let response = try? await URLSession.shared.data(for: head).1,
           response.expectedContentLength > 0 {
            return response.expectedContentLength
        }

        var ranged = URLRequest(url: url, timeoutInterval: 15)
        ranged.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        guard let response = try? await URLSession.shared.data(for: ranged).1 as? HTTPURLResponse,
              let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
              let total = contentRange.split(separator: "/").last.flatMap({ Int64($0) })
        else { return nil }
        return total
    }
}

nonisolated struct UnavailableDownloadMetadataProvider: DownloadMetadataProviding {
    func downloadSize(for urlString: String?) async -> DownloadSizeResult {
        .unknown
    }
}
