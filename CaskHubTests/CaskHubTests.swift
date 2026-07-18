//
//  CaskHubTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 08/02/2026.
//

@testable import CaskHub
import XCTest

final class CaskHubTests: XCTestCase {
    @MainActor
    func test_display_version_strips_packaging_suffixes() {
        XCTAssertEqual(makeCask("test", version: "125.0").displayVersion, "125.0")
        XCTAssertEqual(makeCask("test", version: "125.0,build42").displayVersion, "125.0")
        XCTAssertEqual(makeCask("test", version: "125.0_1").displayVersion, "125.0")
        XCTAssertEqual(makeCask("test", version: "1.2.3-beta").displayVersion, "1.2.3")
        XCTAssertEqual(makeCask("test", version: "2024.10.13").displayVersion, "2024.10.13")
        XCTAssertEqual(makeCask("test", version: "beta").displayVersion, "beta")
    }

    @MainActor
    func test_meta_line_omits_unknown_downloads() {
        XCTAssertEqual(makeCask("test", version: "125.0").metaLine(downloads: "1.2M"), "↓ 1.2M · v125.0")
        XCTAssertEqual(makeCask("test", version: "125.0").metaLine(downloads: nil), "v125.0")
    }

    @MainActor
    func test_update_all_with_empty_queue_clears_flag() async {
        let local = LocalHomebrewService()
        await local.updateAll(tokens: [])
        XCTAssertFalse(local.isUpdatingAll)
    }

    @MainActor
    func test_queued_action_labels_as_queued() {
        XCTAssertEqual(CaskAction.queued.inProgressLabel, "Queued…")
    }
}

final class RequestRecordingProtocol: URLProtocol {
    nonisolated(unsafe) static var requestedHosts: [String] = []

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let host = request.url?.host() {
            Self.requestedHosts.append(host)
        }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

final class ImageCacheManifestGateTests: XCTestCase {
    @MainActor
    private func makeCache() -> ImageCacheService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RequestRecordingProtocol.self]
        return ImageCacheService(session: URLSession(configuration: config))
    }

    @MainActor
    private func cliCask(_ token: String) -> Cask {
        var cask = Cask.preview(token: token)
        cask.artifacts = try? JSONDecoder().decode(
            [ArtifactStanza].self, from: Data(#"[{"binary": true}]"#.utf8)
        )
        return cask
    }

    @MainActor
    func test_cli_cask_missing_from_manifest_makes_no_request() async {
        let cache = makeCache()
        cache.knownIconTokens = { [] }
        RequestRecordingProtocol.requestedHosts = []

        let image = await cache.image(for: cliCask("gate-cli-\(UUID().uuidString)"))

        XCTAssertNil(image)
        XCTAssertEqual(RequestRecordingProtocol.requestedHosts, [])
    }

    @MainActor
    func test_app_cask_missing_from_manifest_probes_only_appfair() async {
        let cache = makeCache()
        cache.knownIconTokens = { [] }
        RequestRecordingProtocol.requestedHosts = []

        _ = await cache.image(for: Cask.preview(token: "gate-app-\(UUID().uuidString)"))

        XCTAssertEqual(RequestRecordingProtocol.requestedHosts, ["github.com"])
    }

    @MainActor
    func test_unknown_manifest_still_probes_caskflow() async {
        let cache = makeCache()
        RequestRecordingProtocol.requestedHosts = []

        _ = await cache.image(for: cliCask("gate-probe-\(UUID().uuidString)"))

        XCTAssertEqual(RequestRecordingProtocol.requestedHosts.first, "cdn.jsdelivr.net")
    }
}
