//
//  IconRefreshTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 09/09/2026.
//  Copyright © 2026 BuildingLink. All rights reserved.

@testable import CaskHub
import Observation
import SwiftUI
import Synchronization
import XCTest

private final class IconRefreshProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) async -> Data?
    static let handler = Mutex<Handler>({ _ in nil })
    static let requests = Mutex<[URLRequest]>([])
    private var responseTask: Task<Void, Never>?

    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let respond = Self.handler.withLock { $0 }
        responseTask = Task {
            guard let data = await respond(request) else {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { responseTask?.cancel() }
}

private actor IconResponseGate {
    private var continuation: CheckedContinuation<Data?, Never>?

    func wait(started: XCTestExpectation) async -> Data? {
        await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }

    func release(_ data: Data) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}

@MainActor
final class IconRefreshTests: XCTestCase {
    private func png(red: Bool) -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let pixels = bitmap.bitmapData!
        for pixel in 0..<4 {
            pixels[pixel * 4] = red ? 255 : 0
            pixels[pixel * 4 + 1] = red ? 0 : 255
            pixels[pixel * 4 + 2] = 0
            pixels[pixel * 4 + 3] = 255
        }
        return bitmap.representation(using: .png, properties: [:])!
    }

    private func cache(_ directory: URL) -> ImageCacheService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [IconRefreshProtocol.self]
        let cache = ImageCacheService(session: URLSession(configuration: config), diskCache: IconDiskCache(directory: directory))
        return cache
    }

    private func metadata(hash: String?) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 1, "hashes": hash.map { ["antinote": $0] } ?? [:]])
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("icon-refresh-\(UUID().uuidString)")
    }

    func test_git_blob_hash_uses_git_header() {
        XCTAssertEqual(ImageCacheService.gitBlobHash(Data("hello".utf8)), "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0")
    }

    func test_metadata_refresh_replaces_only_changed_icons_and_survives_restart() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = png(red: true), fresh = png(red: false)
        let oldHash = ImageCacheService.gitBlobHash(old), freshHash = ImageCacheService.gitBlobHash(fresh)
        XCTAssertNotEqual(oldHash, freshHash)
        let images = cache(directory)
        images.applyIconManifest(try metadata(hash: oldHash))
        let disk = IconDiskCache(directory: directory)
        try await disk.store(old, token: "antinote", generation: 0, fromCaskFlow: true)
        IconRefreshProtocol.requests.withLock { $0 = [] }
        IconRefreshProtocol.handler.withLock { $0 = { _ in fresh } }
        _ = await images.image(for: Cask.preview(token: "antinote"))
        XCTAssertTrue(IconRefreshProtocol.requests.withLock { $0.isEmpty })

        let observed = expectation(description: "hash observation invalidates view task")
        withObservationTracking {
            _ = images.iconHash(for: "antinote")
        } onChange: { observed.fulfill() }
        images.applyIconManifest(try metadata(hash: freshHash))
        await fulfillment(of: [observed], timeout: 2)
        let image = await images.image(for: Cask.preview(token: "antinote"))
        XCTAssertNotNil(image)
        let stored = await disk.loadData(token: "antinote")
        XCTAssertEqual(stored, fresh)
        XCTAssertEqual(IconRefreshProtocol.requests.withLock { $0.count }, 1)
        XCTAssertEqual(IconRefreshProtocol.requests.withLock { $0.first?.cachePolicy }, .reloadIgnoringLocalCacheData)
        XCTAssertNil(IconRefreshProtocol.requests.withLock { $0.first?.url?.query })
        XCTAssertEqual(IconRefreshProtocol.requests.withLock { $0.first?.url?.path },
                       "/gh/alielsokary/CaskFlow@icons/antinote.png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("icon-hashes.json").path))
        let reloadedDisk = IconDiskCache(directory: directory)
        let reloadedBytes = await reloadedDisk.loadData(token: "antinote")
        let reloadedData = try XCTUnwrap(reloadedBytes)
        XCTAssertEqual(ImageCacheService.gitBlobHash(reloadedData), freshHash)
        _ = await images.image(for: Cask.preview(token: "antinote"))
        let restarted = cache(directory)
        restarted.applyIconManifest(try metadata(hash: freshHash))
        _ = await restarted.image(for: Cask.preview(token: "antinote"))
        XCTAssertEqual(IconRefreshProtocol.requests.withLock { $0.count }, 1)
    }

    func test_legacy_icon_refreshes_once_and_stale_cdn_bytes_use_raw_fallback() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = png(red: true), fresh = png(red: false)
        let hash = ImageCacheService.gitBlobHash(fresh)
        let images = cache(directory)
        images.applyIconManifest(try metadata(hash: hash))
        let disk = IconDiskCache(directory: directory)
        try await disk.store(old, token: "antinote", generation: 0, fromCaskFlow: true)
        IconRefreshProtocol.requests.withLock { $0 = [] }
        IconRefreshProtocol.handler.withLock { $0 = { request in
            request.url?.host() == "cdn.jsdelivr.net" ? old : fresh
        } }
        _ = await images.image(for: Cask.preview(token: "antinote"))
        XCTAssertEqual(IconRefreshProtocol.requests.withLock { $0.compactMap { $0.url?.host() } },
                       ["cdn.jsdelivr.net", "raw.githubusercontent.com"])
        let saved = await disk.loadData(token: "antinote")
        XCTAssertEqual(saved, fresh)
        _ = await images.image(for: Cask.preview(token: "antinote"))
        XCTAssertEqual(IconRefreshProtocol.requests.withLock { $0.count }, 2)
    }

    func test_failed_or_stale_download_preserves_old_icon_and_retries() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = png(red: true), fresh = png(red: false)
        let oldHash = ImageCacheService.gitBlobHash(old)
        let images = cache(directory)
        images.applyIconManifest(try metadata(hash: ImageCacheService.gitBlobHash(fresh)))
        let disk = IconDiskCache(directory: directory)
        try await disk.store(old, token: "antinote", generation: 0, fromCaskFlow: true)
        for response in [nil, old] as [Data?] {
            IconRefreshProtocol.handler.withLock { $0 = { _ in response } }
            let image = await images.image(for: Cask.preview(token: "antinote"))
            XCTAssertNotNil(image)
            let saved = await disk.loadData(token: "antinote")
            XCTAssertEqual(saved, old)
            XCTAssertEqual(ImageCacheService.gitBlobHash(try XCTUnwrap(saved)), oldHash)
        }
        IconRefreshProtocol.handler.withLock { $0 = { _ in fresh } }
        _ = await images.image(for: Cask.preview(token: "antinote"))
        let saved = await disk.loadData(token: "antinote")
        XCTAssertEqual(saved, fresh)
    }

    func test_late_old_download_cannot_overwrite_new_revision() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = png(red: true), fresh = png(red: false)
        let oldHash = ImageCacheService.gitBlobHash(old), freshHash = ImageCacheService.gitBlobHash(fresh)
        let images = cache(directory)
        images.applyIconManifest(try metadata(hash: oldHash))
        let gate = IconResponseGate()
        let started = expectation(description: "old download suspended")
        let first = Mutex(true)
        IconRefreshProtocol.handler.withLock { $0 = { _ in
            if first.withLock({ value in defer { value = false }; return value }) {
                return await gate.wait(started: started)
            }
            return fresh
        } }
        let oldTask = Task { await images.image(for: Cask.preview(token: "antinote")) }
        await fulfillment(of: [started], timeout: 3)
        images.applyIconManifest(try metadata(hash: freshHash))
        _ = await images.image(for: Cask.preview(token: "antinote"))
        await gate.release(old)
        _ = await oldTask.value
        let disk = IconDiskCache(directory: directory)
        let data = await disk.loadData(token: "antinote")
        XCTAssertEqual(data, fresh)
        XCTAssertEqual(ImageCacheService.gitBlobHash(try XCTUnwrap(data)), freshHash)
    }

    func test_visible_icon_retries_mismatch_on_independent_manifest_refresh() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = png(red: true), fresh = png(red: false)
        let images = cache(directory)
        let oldHash = ImageCacheService.gitBlobHash(old)
        images.applyIconManifest(try metadata(hash: oldHash))
        let disk = IconDiskCache(directory: directory)
        try await disk.store(old, token: "antinote", generation: 0, fromCaskFlow: true)
        IconRefreshProtocol.handler.withLock { $0 = { _ in fresh } }
        let host = NSHostingView(rootView: CaskIconView(cask: Cask.preview(token: "antinote"))
            .environment(images))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 60, height: 60),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        await waitForColor(in: host, red: true)
        let manifest = try metadata(hash: ImageCacheService.gitBlobHash(fresh))
        let pngRequests = Mutex(0)
        let attempted = expectation(description: "both mutable image endpoints returned stale bytes")
        IconRefreshProtocol.handler.withLock { $0 = { request in
            if request.url?.lastPathComponent == "icons.json" { return manifest }
            if pngRequests.withLock({ $0 += 1; return $0 }) == 2 { attempted.fulfill() }
            return old
        } }
        await images.refreshIconManifest(force: true)
        await fulfillment(of: [attempted], timeout: 5)
        XCTAssertTrue(containsColor(in: host, red: true))
        IconRefreshProtocol.handler.withLock { $0 = { request in
            request.url?.lastPathComponent == "icons.json" ? manifest : fresh
        } }
        // The hash stays the same; manual refresh must retry the failed image.
        await images.refreshIconManifest(force: true)
        await waitForColor(in: host, red: false)
    }

    private func waitForColor(in view: NSView, red: Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if containsColor(in: view, red: red) { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Expected the visible icon to become \(red ? "red" : "green")")
    }

    private func containsColor(in view: NSView, red: Bool) -> Bool {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        for row in 0..<bitmap.pixelsHigh {
            for column in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { continue }
                if red ? (color.redComponent > 0.8 && color.greenComponent < 0.2)
                    : (color.greenComponent > 0.8 && color.redComponent < 0.2) { return true }
            }
        }
        return false
    }

    func test_manifest_refresh_is_independent_throttled_and_preserves_good_data_on_failure() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let images = cache(directory)
        let hash = ImageCacheService.gitBlobHash(png(red: false))
        let manifest = try metadata(hash: hash)
        IconRefreshProtocol.requests.withLock { $0 = [] }
        IconRefreshProtocol.handler.withLock { $0 = { _ in manifest } }
        await images.refreshIconManifest()
        await images.refreshIconManifest()
        XCTAssertEqual(images.iconHash(for: "antinote"), hash)
        XCTAssertEqual(IconRefreshProtocol.requests.withLock { $0.count }, 1)
        XCTAssertEqual(IconRefreshProtocol.requests.withLock { $0.first?.url?.path },
                       "/alielsokary/CaskFlow/icons/icons.json")
        for data in [nil, Data("{}".utf8), Data(#"{"version":2,"hashes":{}}"#.utf8),
                     try metadata(hash: "invalid")] as [Data?] {
            IconRefreshProtocol.handler.withLock { $0 = { _ in data } }
            await images.refreshIconManifest(force: true)
            XCTAssertEqual(images.iconHash(for: "antinote"), hash)
        }
        XCTAssertEqual(IconRefreshProtocol.requests.withLock { $0.count }, 5)
    }
}
