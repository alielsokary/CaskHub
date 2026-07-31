//
//  ImageCacheService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 27/03/2026.
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ImageCacheService {
    private let memoryCache = NSCache<NSString, NSImage>()
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]
    private var upgradeInFlight: Set<String> = []
    private let session: URLSession
    private let diskCache: IconDiskCache

    /// Manifest of tokens with an icon on the CaskFlow icons branch, from
    /// categories.json — absent tokens are guaranteed 404s, never requested.
    /// nil = manifest unknown (old category data) → fall back to probing.
    var knownIconTokens: () -> Set<String>? = { nil }

    private static let missRetryInterval: TimeInterval = 24 * 60 * 60
    // The manifest vouches the icon exists, so a recorded miss is publication
    // or CDN lag, not absence - misses recorded before the manifest gained the
    // token would otherwise hide the icon for a full day.
    private static let vouchedMissRetryInterval: TimeInterval = 15 * 60

    init(session: URLSession = .shared, diskCache: IconDiskCache = .shared) {
        self.session = session
        self.diskCache = diskCache
        memoryCache.countLimit = 500
        Task {
            do {
                try await diskCache.purgeGeneratedIconsIfNeeded()
            } catch {
                CrashReporter.capture(error)
            }
        }
    }

    func image(for cask: Cask) async -> NSImage? {
        let token = cask.token

        if let cached = memoryCache.object(forKey: token as NSString) {
            return cached
        }
        let generation = await diskCache.currentGeneration()

        if cask.isCLI {
            await purgeStaleCLIIcon(token: token)
        }

        if let data = await diskCache.loadData(token: token),
           let diskImage = NSImage(data: data),
           diskImage.isValid {
            memoryCache.setObject(diskImage, forKey: token as NSString)
            await maybeUpgradeFallbackIcon(token: token, generation: generation)
            return diskImage
        }

        let inManifest = knownIconTokens()?.contains(token) ?? true
        if cask.isCLI, !inManifest {
            return nil
        }

        if await diskCache.hasRecentMiss(
            token: token,
            retryInterval: inManifest
                ? Self.vouchedMissRetryInterval
                : Self.missRetryInterval
        ) {
            return nil
        }

        if let existing = inFlightTasks[token] {
            return await existing.value
        }

        let task = Task {
            await fetchImage(
                for: cask,
                inManifest: inManifest,
                generation: generation
            )
        }

        inFlightTasks[token] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: token)
        return result
    }

    func clearCache() async {
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        upgradeInFlight.removeAll()
        memoryCache.removeAllObjects()
        do {
            try await diskCache.clear()
        } catch {
            CrashReporter.capture(error)
        }
        // A task already returning to the main actor may have populated memory
        // while the disk actor was clearing. The generation check rejects its write.
        memoryCache.removeAllObjects()
    }

    // MARK: - Private

    private func fetchImage(
        for cask: Cask,
        inManifest: Bool,
        generation: UInt64
    ) async -> NSImage? {
        let token = cask.token
        var sawHTTPResponse = false
        func fetch(_ url: URL) async -> NSImage? {
            let (image, responded) = await downloadImage(from: url)
            sawHTTPResponse = sawHTTPResponse || responded
            return image
        }

        if inManifest {
            for url in CaskIconURL.caskFlowIconURLs(for: token) {
                if let image = await fetch(url) {
                    await cache(
                        image: image,
                        token: token,
                        generation: generation,
                        fromCaskFlow: true
                    )
                    return image
                }
            }
        }

        if !cask.isCLI,
           let url = CaskIconURL.appFairIconURL(for: token),
           let image = await fetch(url) {
            await cache(image: image, token: token, generation: generation)
            return image
        }

        if sawHTTPResponse {
            do {
                try await diskCache.recordMiss(token: token, generation: generation)
            } catch {
                CrashReporter.capture(error)
            }
        }
        return nil
    }

    private func downloadImage(from url: URL) async -> (image: NSImage?, gotResponse: Bool) {
        guard let (data, response) = try? await session.data(from: url),
              let httpResponse = response as? HTTPURLResponse
        else {
            return (nil, false)
        }
        guard httpResponse.statusCode == 200,
              let image = NSImage(data: data),
              image.isValid
        else {
            return (nil, true)
        }
        return (image, true)
    }

    private func cache(
        image: NSImage,
        token: String,
        generation: UInt64,
        fromCaskFlow: Bool = false
    ) async {
        guard await diskCache.isCurrent(generation) else { return }
        memoryCache.setObject(image, forKey: token as NSString)
        guard let pngData = await Self.pngData(for: image) else { return }
        do {
            try await diskCache.store(
                pngData,
                token: token,
                generation: generation,
                fromCaskFlow: fromCaskFlow
            )
        } catch {
            CrashReporter.capture(error)
        }
    }

    // MARK: - CLI cutover purge

    private static let cliIconCutover = Date(timeIntervalSince1970: 1_783_598_400)

    private func purgeStaleCLIIcon(token: String) async {
        guard await diskCache.purgeStaleCLIIcon(
            token: token,
            before: Self.cliIconCutover
        ) else { return }
        let urlCache = session.configuration.urlCache ?? .shared
        for url in CaskIconURL.caskFlowIconURLs(for: token) {
            urlCache.removeCachedResponse(for: URLRequest(url: url))
        }
    }

    // MARK: - Fallback upgrade

    private func maybeUpgradeFallbackIcon(token: String, generation: UInt64) async {
        if let known = knownIconTokens(), !known.contains(token) {
            return
        }
        guard await diskCache.fallbackNeedsUpgrade(
            token: token,
            retryInterval: Self.missRetryInterval
        ),
            !upgradeInFlight.contains(token)
        else {
            return
        }
        upgradeInFlight.insert(token)
        Task {
            for url in CaskIconURL.caskFlowIconURLs(for: token) {
                let (image, _) = await downloadImage(from: url)
                if let image {
                    await cache(
                        image: image,
                        token: token,
                        generation: generation,
                        fromCaskFlow: true
                    )
                    upgradeInFlight.remove(token)
                    return
                }
            }
            try? await diskCache.touchFallback(token: token, generation: generation)
            upgradeInFlight.remove(token)
        }
    }

    private nonisolated static func pngData(for image: NSImage) async -> Data? {
        await Task.detached(priority: .utility) {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else {
                return nil
            }
            return pngData
        }.value
    }
}
