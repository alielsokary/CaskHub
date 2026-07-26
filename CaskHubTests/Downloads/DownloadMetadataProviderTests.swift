//
//  DownloadMetadataProviderTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 25/07/2026.
//

@testable import CaskHub
import XCTest

final class DownloadMetadataProviderTests: XCTestCase {
    func test_provider_caches_content_length_by_url() async {
        let counter = DownloadLoaderCounter(result: 42_000)
        let provider = DownloadMetadataProvider { url in
            await counter.load(url)
        }

        let first = await provider.downloadSize(for: "https://example.com/app.dmg")
        let second = await provider.downloadSize(for: "https://example.com/app.dmg")
        let callCount = await counter.callCount

        XCTAssertEqual(first, .known(42_000))
        XCTAssertEqual(second, first)
        XCTAssertEqual(callCount, 1)
    }

    func test_provider_rejects_missing_and_invalid_urls_without_loading() async {
        let counter = DownloadLoaderCounter(result: 42_000)
        let provider = DownloadMetadataProvider { url in
            await counter.load(url)
        }

        let missing = await provider.downloadSize(for: nil)
        let invalid = await provider.downloadSize(for: "")
        let callCount = await counter.callCount

        XCTAssertEqual(missing, .unknown)
        XCTAssertEqual(invalid, .unknown)
        XCTAssertEqual(callCount, 0)
    }
}

private actor DownloadLoaderCounter {
    let result: Int64?
    private(set) var callCount = 0

    init(result: Int64?) {
        self.result = result
    }

    func load(_: URL) -> Int64? {
        callCount += 1
        return result
    }
}
