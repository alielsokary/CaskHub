//
//  TapCaskIconTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 12/11/2026.
//

@testable import CaskHub
import Synchronization
import XCTest

private final class TapIconProtocol: URLProtocol {
    static let served = Mutex<Set<String>>([])
    static let requests = Mutex<[String]>([])

    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.requests.withLock { $0.append(url.absoluteString) }
        let body = Self.served.withLock { $0.contains(url.absoluteString) } ? TapCaskIconTests.png : nil
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class TapCaskIconTests: XCTestCase {
    func test_installed_tap_cask_points_at_its_app_in_every_app_folder() {
        let apps = URL(fileURLWithPath: "/tmp/apps-a"), more = URL(fileURLWithPath: "/tmp/apps-b")
        let service = makeService(directories: [apps, more])
        updateInstalledCask(sillInstallation(tap: "saffsanity/sill"), in: service)

        XCTAssertEqual(
            service.installedAppCandidates(for: sill),
            [apps.appendingPathComponent("Sill.app"), more.appendingPathComponent("Sill.app")]
        )
    }

    func test_not_installed_or_twin_installed_has_no_app() {
        let service = makeService(directories: [URL(fileURLWithPath: "/tmp/apps")])
        XCTAssertTrue(service.installedAppCandidates(for: sill).isEmpty)

        updateInstalledCask(sillInstallation(tap: "homebrew/cask"), in: service)
        XCTAssertTrue(service.installedAppCandidates(for: sill).isEmpty, "the official twin's app is not this cask's")
    }

    func test_icon_comes_from_the_first_app_that_exists() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tap-icon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Sill.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let cache = ImageCacheService(diskCache: IconDiskCache(directory: root.appendingPathComponent("cache")))

        let missing = await cache.installedAppIcon(for: sill, candidates: [root.appendingPathComponent("Nope.app")])
        let found = await cache.installedAppIcon(for: sill, candidates: [root.appendingPathComponent("Nope.app"), app])

        XCTAssertNil(missing)
        XCTAssertNotNil(found)
    }

    func test_caskflow_urls_put_tap_icons_under_taps() {
        XCTAssertEqual(CaskIconURL.caskFlowIconURLs(for: "saffsanity/sill/sill").map(\.absoluteString), [
            "https://cdn.jsdelivr.net/gh/alielsokary/CaskFlow@icons/taps/saffsanity/sill/sill.png",
            "https://raw.githubusercontent.com/alielsokary/CaskFlow/icons/taps/saffsanity/sill/sill.png"
        ])
        XCTAssertEqual(CaskIconURL.caskFlowIconURLs(for: "figma").first?.lastPathComponent, "figma.png")
    }

    func test_disk_cache_names_tap_icons_without_slashes() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = IconDiskCache(directory: root)

        try await disk.store(Data("png".utf8), token: "a__b/r/t", generation: 0, fromCaskFlow: true)
        try await disk.store(Data("other".utf8), token: "a/b__r/t", generation: 0, fromCaskFlow: true)

        let files = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".png") }.sorted()
        XCTAssertEqual(files.count, 2, "distinct references never share a file")
        XCTAssertFalse(files.contains { $0.contains("/") })
        let stored = await disk.loadData(token: "a__b/r/t")
        XCTAssertEqual(stored, Data("png".utf8))
    }

    func test_manifest_hashes_tap_icons_by_reference() {
        let cache = ImageCacheService(diskCache: IconDiskCache(directory: temporaryDirectory()))
        let hash = String(repeating: "a", count: 40)

        XCTAssertTrue(cache.applyIconManifest(Data(#"{"version": 1, "hashes": {}, "taps": {"saffsanity/sill/sill": "\#(hash)"}}"#.utf8)))

        XCTAssertEqual(cache.iconHash(for: "saffsanity/sill/sill"), hash)
        XCTAssertFalse(cache.applyIconManifest(Data(#"{"version": 1, "hashes": {}, "taps": {"../evil": "\#(hash)"}}"#.utf8)))
    }

    func test_covered_tap_cask_loads_its_caskflow_icon_before_the_app_icon() async throws {
        let app = try makeApp()
        let cache = makeCache(serving: ["https://cdn.jsdelivr.net/gh/alielsokary/CaskFlow@icons/taps/saffsanity/sill/sill.png"])
        cache.knownTapIconRefs = { ["saffsanity/sill/sill"] }

        let image = await cache.icon(for: sill, installedCandidates: [app])

        XCTAssertNotNil(image)
        XCTAssertEqual(TapIconProtocol.requests.withLock { $0 }.count, 1)
        XCTAssertNotNil(cache.cachedImage(for: "saffsanity/sill/sill"), "the CaskFlow icon, not the app's, is cached under the reference")
    }

    func test_aliased_tap_cask_shows_the_official_icon() async {
        let official = "https://cdn.jsdelivr.net/gh/alielsokary/CaskFlow@icons/ngrok.png"
        let cache = makeCache(serving: [official])
        cache.officialAlias = { $0 == "ngrok/ngrok/ngrok" ? "ngrok" : nil }

        let ngrok = CaskFileTextParser.cask(fromSource: "", token: "ngrok", tap: "ngrok/ngrok")
        let image = await cache.icon(for: ngrok, installedCandidates: [])

        XCTAssertNotNil(image)
        XCTAssertEqual(TapIconProtocol.requests.withLock { $0 }.first, official)
    }

    func test_uncovered_tap_cask_uses_its_app_icon_and_requests_nothing() async throws {
        let app = try makeApp()
        let cache = makeCache(serving: [])

        let installed = await cache.icon(for: sill, installedCandidates: [app])
        let other = CaskFileTextParser.cask(fromSource: "", token: "other", tap: "u/r")
        let notInstalled = await cache.icon(for: other, installedCandidates: [])

        XCTAssertNotNil(installed)
        XCTAssertNil(notInstalled)
        XCTAssertEqual(TapIconProtocol.requests.withLock { $0 }, [])
    }

    // MARK: - Helpers

    static let png: Data = {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        return bitmap.representation(using: .png, properties: [:])!
    }()

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tap-icon-\(UUID().uuidString)")
    }

    private func makeCache(serving urls: Set<String>) -> ImageCacheService {
        TapIconProtocol.served.withLock { $0 = urls }
        TapIconProtocol.requests.withLock { $0 = [] }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TapIconProtocol.self]
        let root = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return ImageCacheService(session: URLSession(configuration: config), diskCache: IconDiskCache(directory: root))
    }

    private func makeApp() throws -> URL {
        let root = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Sill.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        return app
    }

    private let sill = CaskFileTextParser.cask(fromSource: "", token: "sill", tap: "saffsanity/sill")

    private func makeService(directories: [URL]) -> LocalHomebrewService {
        LocalHomebrewService(defaults: makeScratchDefaults("tap-icon-\(UUID().uuidString)")) {
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.applicationDirectories = directories
        }
    }

    private func sillInstallation(tap: String) -> LocalCaskInstallation {
        LocalCaskInstallation(token: "sill", installedVersion: "0.6.1", installedAt: nil, appBundleNames: ["Sill.app"], tap: tap)
    }
}
