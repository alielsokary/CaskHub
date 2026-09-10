//
//  ImageCacheService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 27/03/2026.
//

import AppKit
import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class ImageCacheService {
    private let memoryCache = NSCache<NSString, NSImage>()
    private var memoryHashes: [String: String] = [:]
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]
    private var upgradeInFlight: Set<String> = []
    private let session: URLSession
    private let diskCache: IconDiskCache

    /// Manifest of tokens with an icon on the CaskFlow icons branch, from
    /// categories.json — absent tokens are guaranteed 404s, never requested.
    /// nil = manifest unknown (old category data) → fall back to probing.
    var knownIconTokens: () -> Set<String>? = { nil }
    private var iconHashes: [String: String]?
    private var lastManifestAttempt: Date?
    private var isRefreshingManifest = false
    private(set) var iconRefreshRevision: UInt64 = 0

    func iconHash(for token: String) -> String? {
        iconHashes?[token]
    }

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

        if let hash = iconHash(for: token) {
            return await hashedImage(for: cask, hash: hash)
        }

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
            guard !Task.isCancelled, await diskCache.isCurrent(generation) else { return nil }
            if iconHash(for: token) != nil { return await image(for: cask) }
            memoryCache.setObject(diskImage, forKey: token as NSString)
            memoryHashes.removeValue(forKey: token)
            await maybeUpgradeFallbackIcon(token: token, generation: generation)
            return diskImage
        }

        let inManifest = iconHashes.map { $0[token] != nil } ?? knownIconTokens()?.contains(token) ?? true
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
        memoryHashes.removeAll()
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
        fromCaskFlow: Bool = false,
        expectedHash: String? = nil
    ) async {
        guard await diskCache.isCurrent(generation), iconHash(for: token) == expectedHash else { return }
        guard let pngData = await Self.pngData(for: image) else { return }
        guard !Task.isCancelled, iconHash(for: token) == expectedHash else { return }
        do {
            guard try await diskCache.store(
                pngData,
                token: token,
                generation: generation,
                fromCaskFlow: fromCaskFlow
            ) else { return }
            guard !Task.isCancelled, await diskCache.isCurrent(generation),
                  iconHash(for: token) == expectedHash else { return }
            memoryCache.setObject(image, forKey: token as NSString)
            memoryHashes.removeValue(forKey: token)
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
            !upgradeInFlight.contains(token), iconHash(for: token) == nil
        else {
            return
        }
        upgradeInFlight.insert(token)
        let key = "\(token):fallback"
        inFlightTasks[key] = Task {
            defer {
                upgradeInFlight.remove(token)
                inFlightTasks.removeValue(forKey: key)
            }
            for url in CaskIconURL.caskFlowIconURLs(for: token) {
                let (image, _) = await downloadImage(from: url)
                if let image {
                    await cache(
                        image: image,
                        token: token,
                        generation: generation,
                        fromCaskFlow: true
                    )
                    return image
                }
            }
            try? await diskCache.touchFallback(token: token, generation: generation)
            return nil
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

extension ImageCacheService {
    private func hashedImage(for cask: Cask, hash: String) async -> NSImage? {
        let token = cask.token
        if memoryHashes[token] == hash,
           let image = memoryCache.object(forKey: token as NSString) { return image }
        let generation = await diskCache.currentGeneration()
        let key = "\(token):\(hash):\(generation)"
        guard iconHash(for: token) == hash else { return await image(for: cask) }
        for (otherKey, task) in inFlightTasks where otherKey != key
            && (otherKey == token || otherKey.hasPrefix("\(token):")) {
            task.cancel()
        }
        if let task = inFlightTasks[key] { return await task.value }
        let task = Task {
            await refreshHashedImage(for: cask, hash: hash, generation: generation)
        }
        inFlightTasks[key] = task
        let image = await task.value
        inFlightTasks.removeValue(forKey: key)
        return image
    }

    private func refreshHashedImage(for cask: Cask, hash: String, generation: UInt64) async -> NSImage? {
        let token = cask.token
        var previous = memoryCache.object(forKey: token as NSString)
        if let data = await diskCache.loadData(token: token),
           let image = NSImage(data: data), image.isValid {
            previous = image
            if Self.gitBlobHash(data) == hash {
                guard !Task.isCancelled, await diskCache.isCurrent(generation),
                      iconHash(for: token) == hash else { return previous }
                memoryCache.setObject(image, forKey: token as NSString)
                memoryHashes[token] = hash
                return image
            }
        }
        if let image = await downloadHashedImage(token: token, hash: hash, generation: generation) { return image }
        guard !Task.isCancelled, iconHash(for: token) == hash else { return previous }
        if previous == nil, !cask.isCLI, let url = CaskIconURL.appFairIconURL(for: token) {
            let (image, _) = await downloadImage(from: url)
            if let image {
                await cache(image: image, token: token, generation: generation, expectedHash: hash)
                return image
            }
        }
        return previous
    }

    private func downloadHashedImage(token: String, hash: String, generation: UInt64) async -> NSImage? {
        for url in CaskIconURL.caskFlowIconURLs(for: token) {
            guard !Task.isCancelled else { return nil }
            // Mutable endpoints may lag. Only matching bytes may replace the cache.
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  Self.gitBlobHash(data) == hash,
                  let image = NSImage(data: data), image.isValid else { continue }
            guard !Task.isCancelled, await diskCache.isCurrent(generation),
                  iconHash(for: token) == hash else { return nil }
            do {
                guard try await diskCache.store(
                    data, token: token, generation: generation, fromCaskFlow: true
                ) else { return nil }
            } catch {
                CrashReporter.capture(error)
                return nil
            }
            guard !Task.isCancelled, await diskCache.isCurrent(generation),
                  iconHash(for: token) == hash else { return nil }
            memoryCache.setObject(image, forKey: token as NSString)
            memoryHashes[token] = hash
            return image
        }
        return nil
    }

    nonisolated static func gitBlobHash(_ data: Data) -> String {
        var digest = Insecure.SHA1()
        digest.update(data: Data("blob \(data.count)\0".utf8))
        digest.update(data: data)
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension ImageCacheService {
    /// Independent of category releases. Failed attempts retain the last manifest.
    func refreshIconManifest(force: Bool = false) async {
        guard !isRefreshingManifest,
              force || lastManifestAttempt.map({ Date().timeIntervalSince($0) >= 15 * 60 }) ?? true else { return }
        isRefreshingManifest = true
        lastManifestAttempt = Date()
        defer {
            isRefreshingManifest = false
            // Retry visible stale icons even when the manifest itself is unchanged.
            iconRefreshRevision &+= 1
        }
        let url = URL(string: "https://raw.githubusercontent.com/alielsokary/CaskFlow/icons/icons.json")!
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        guard let (data, response) = try? await session.data(for: request),
              !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        applyIconManifest(data)
    }

    @discardableResult
    func applyIconManifest(_ data: Data) -> Bool {
        guard let manifest = try? JSONDecoder().decode(IconManifest.self, from: data),
              manifest.version == 1,
              manifest.hashes.allSatisfy({ token, hash in
                  token.range(of: #"^[a-z0-9][a-z0-9+@._-]*$"#, options: .regularExpression) != nil
                      && hash.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil
              }) else { return false }
        iconHashes = manifest.hashes
        return true
    }

    private nonisolated struct IconManifest: Decodable {
        let version: Int
        let hashes: [String: String]
    }
}
