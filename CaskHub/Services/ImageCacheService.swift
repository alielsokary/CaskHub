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

    /// How long a full-chain miss suppresses re-fetching. Misses re-try daily
    /// so users pick up newly backfilled CaskFlow icons without launch chatter.
    private static let missRetryInterval: TimeInterval = 24 * 60 * 60

    private static let cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("CaskHub/icons", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            // Disk cache is dead for the session — icons fall back to memory-only.
            CrashReporter.capture(error)
        }
        return dir
    }()

    init(session: URLSession = .shared) {
        self.session = session
        memoryCache.countLimit = 500
        Self.purgeGeneratedIconsIfNeeded()
    }

    func image(for cask: Cask) async -> NSImage? {
        let token = cask.token

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: token as NSString) {
            return cached
        }

        // CLI casks: icons cached before the cutover may since have been
        // retired by CaskFlow's curated CLI tier — drop and refetch once.
        if cask.isCLI {
            purgeStaleCLIIcon(token: token)
        }

        // 2. Disk cache — fallback-tier hits also schedule a background
        // CaskFlow upgrade check (at most daily), so icons cached from
        // favicon/avatar before CaskFlow coverage arrived aren't pinned forever.
        if let diskImage = loadFromDisk(token: token) {
            memoryCache.setObject(diskImage, forKey: token as NSString)
            maybeUpgradeFallbackIcon(token: token)
            return diskImage
        }

        // 3. Recent-miss cooldown: every tier failed with real HTTP responses
        // within the last day — skip the whole chain until the cooldown lapses.
        if hasRecentMiss(token: token) {
            return nil
        }

        // 4. Coalesce in-flight requests
        if let existing = inFlightTasks[token] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            // Track whether any tier got an actual HTTP response: a miss is
            // only recorded when servers answered (offline must not poison
            // the cooldown for a day).
            var sawHTTPResponse = false
            func fetch(_ url: URL) async -> NSImage? {
                let (image, responded) = await self.downloadImage(from: url)
                sawHTTPResponse = sawHTTPResponse || responded
                return image
            }

            // Tier 0: CaskFlow original icon (our own extraction pipeline —
            // jsDelivr CDN with raw.githubusercontent fallback, backfilling)
            for url in CaskIconURL.caskFlowIconURLs(for: token) {
                if let image = await fetch(url) {
                    cache(image: image, token: token, fromCaskFlow: true)
                    return image
                }
            }

            // Tier 1: App-Fair app icon (also original; frozen pre-2022 —
            // covers some casks CaskFlow can't extract today). Skipped for
            // CLI casks: their icon policy is CaskFlow's alone — anything
            // else falls through to the app's CLI tile.
            if !cask.isCLI,
               let url = CaskIconURL.appFairIconURL(for: token),
               let image = await fetch(url) {
                cache(image: image, token: token)
                return image
            }

            // No generated fallbacks (favicons, avatars) — by design the
            // placeholder shows until an original icon exists.
            if sawHTTPResponse {
                markMiss(token: token)
            }
            return nil
        }

        inFlightTasks[token] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: token)
        return result
    }

    // MARK: - Private

    /// gotResponse distinguishes "server said no" (404 etc.) from transport
    /// failure (offline) — only real responses may arm the miss cooldown.
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

    private func cache(image: NSImage, token: String, fromCaskFlow: Bool = false) {
        memoryCache.setObject(image, forKey: token as NSString)
        saveToDisk(image: image, token: token)
        try? FileManager.default.removeItem(at: missMarkerPath(for: token))
        if fromCaskFlow {
            // Terminal quality — never re-checked.
            try? FileManager.default.removeItem(at: fallbackMarkerPath(for: token))
        } else {
            // Fallback tier (App-Fair/favicon/avatar): upgrade-eligible.
            // mtime = now, so the first CaskFlow re-check happens tomorrow —
            // CaskFlow necessarily missed moments ago on this same chain run.
            try? Data().write(to: fallbackMarkerPath(for: token), options: .atomic)
        }
    }

    // MARK: - CLI cutover purge

    /// 2026-07-09 12:00 UTC — CaskFlow's curated-CLI icon cleanup plus the
    /// jsDelivr branch TTL that kept serving the retired files.
    private static let cliIconCutover = Date(timeIntervalSince1970: 1_783_598_400)

    private func purgeStaleCLIIcon(token: String) {
        let path = diskPath(for: token)
        guard let mtime = try? FileManager.default
            .attributesOfItem(atPath: path.path)[.modificationDate] as? Date,
            mtime < Self.cliIconCutover
        else {
            return
        }
        try? FileManager.default.removeItem(at: path)
        try? FileManager.default.removeItem(at: fallbackMarkerPath(for: token))
        // jsDelivr's long max-age would replay the retired icon's cached 200
        // from URLCache — evict so the refetch hits the network.
        let urlCache = session.configuration.urlCache ?? .shared
        for url in CaskIconURL.caskFlowIconURLs(for: token) {
            urlCache.removeCachedResponse(for: URLRequest(url: url))
        }
    }

    // MARK: - Fallback upgrade

    private func fallbackMarkerPath(for token: String) -> URL {
        Self.cacheDirectory.appendingPathComponent("\(token).fallback")
    }

    /// A disk-cached fallback icon is re-checked against CaskFlow at most once
    /// per missRetryInterval — lazily, only when the cask is actually shown.
    /// A hit permanently replaces the cached icon and retires the marker.
    private func maybeUpgradeFallbackIcon(token: String) {
        let marker = fallbackMarkerPath(for: token)
        guard let mtime = try? FileManager.default
            .attributesOfItem(atPath: marker.path)[.modificationDate] as? Date,
            Date().timeIntervalSince(mtime) >= Self.missRetryInterval,
            !upgradeInFlight.contains(token)
        else {
            return
        }
        upgradeInFlight.insert(token)
        Task {
            for url in CaskIconURL.caskFlowIconURLs(for: token) {
                let (image, _) = await downloadImage(from: url)
                if let image {
                    cache(image: image, token: token, fromCaskFlow: true)
                    upgradeInFlight.remove(token)
                    return
                }
            }
            // Still not on CaskFlow — reset the daily timer.
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: marker.path
            )
            upgradeInFlight.remove(token)
        }
    }

    /// One-time migration: purge cached icons that predate the original-only
    /// chain. Anything carrying a fallback marker (or unmarked from before
    /// tier tracking) may be a favicon/avatar — delete it and let the cask
    /// refetch through CaskFlow → App-Fair. CaskFlow-tier caches are unmarked
    /// only if fetched after tier tracking, so we key off the v1 flag:
    /// pre-tracking installs purge everything marked or migrated.
    private nonisolated static func purgeGeneratedIconsIfNeeded() {
        Task.detached(priority: .utility) {
            let dir = await Self.cacheDirectory
            let flag = dir.appendingPathComponent(".generated-purge-done")
            guard !FileManager.default.fileExists(atPath: flag.path) else { return }
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            )) ?? []
            for marker in files where marker.pathExtension == "fallback" {
                let token = marker.deletingPathExtension().lastPathComponent
                try? FileManager.default.removeItem(
                    at: dir.appendingPathComponent("\(token).png")
                )
                try? FileManager.default.removeItem(at: marker)
            }
            // Retired artifacts from the avatar tier and the v1 migration.
            try? FileManager.default.removeItem(
                at: dir.deletingLastPathComponent()
                    .appendingPathComponent("github_owner_types.json")
            )
            try? FileManager.default.removeItem(
                at: dir.appendingPathComponent(".tier-migration-done")
            )
            try? Data().write(to: flag, options: .atomic)
        }
    }

    // MARK: - Miss cooldown

    private func missMarkerPath(for token: String) -> URL {
        Self.cacheDirectory.appendingPathComponent("\(token).miss")
    }

    private func hasRecentMiss(token: String) -> Bool {
        let path = missMarkerPath(for: token)
        guard let mtime = try? FileManager.default
            .attributesOfItem(atPath: path.path)[.modificationDate] as? Date
        else {
            return false
        }
        return Date().timeIntervalSince(mtime) < Self.missRetryInterval
    }

    private func markMiss(token: String) {
        try? Data().write(to: missMarkerPath(for: token), options: .atomic)
    }

    private func diskPath(for token: String) -> URL {
        Self.cacheDirectory.appendingPathComponent("\(token).png")
    }

    private func loadFromDisk(token: String) -> NSImage? {
        let path = diskPath(for: token)
        guard FileManager.default.fileExists(atPath: path.path),
              let image = NSImage(contentsOf: path),
              image.isValid
        else {
            return nil
        }
        return image
    }

    private nonisolated func saveToDisk(image: NSImage, token: String) {
        Task.detached(priority: .utility) {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else {
                return
            }
            let path = await Self.cacheDirectory.appendingPathComponent("\(token).png")
            do {
                try pngData.write(to: path, options: .atomic)
            } catch {
                await CrashReporter.capture(error)
            }
        }
    }
}
