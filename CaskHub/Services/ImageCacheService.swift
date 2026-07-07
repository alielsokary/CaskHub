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
    private var ownerTypeCache: [String: Bool] = [:] // owner -> isOrg

    /// How long a full-chain miss suppresses re-fetching. Misses re-try daily
    /// so users pick up newly backfilled CaskKit icons without launch chatter.
    private static let missRetryInterval: TimeInterval = 24 * 60 * 60

    private static let cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("CaskHub/icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let ownerTypeCachePath: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("CaskHub/github_owner_types.json")
    }()

    /// Shared session that doesn't follow redirects — used to inspect github.com/orgs/{owner} status codes
    private static let noRedirectSession: URLSession = {
        URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
    }()

    init(session: URLSession = .shared) {
        self.session = session
        memoryCache.countLimit = 500
        ownerTypeCache = Self.loadOwnerTypeCache()
        Self.migrateUntieredCacheIfNeeded()
    }

    func image(for cask: Cask) async -> NSImage? {
        let token = cask.token

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: token as NSString) {
            return cached
        }

        // 2. Disk cache — fallback-tier hits also schedule a background
        // CaskKit upgrade check (at most daily), so icons cached from
        // favicon/avatar before CaskKit coverage arrived aren't pinned forever.
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

            // Tier 0: CaskKit original icon (our own extraction pipeline —
            // jsDelivr CDN with raw.githubusercontent fallback, backfilling)
            for url in CaskIconURL.caskKitIconURLs(for: token) {
                if let image = await fetch(url) {
                    cache(image: image, token: token, fromCaskKit: true)
                    return image
                }
            }

            // Tier 1: App-Fair app icon (original icons, stale — pre-2022 coverage)
            if let url = CaskIconURL.appIconURL(for: token),
               let image = await fetch(url) {
                cache(image: image, token: token)
                return image
            }

            // Tier 2: Homepage favicon via icon.horse (best for apps with dedicated websites)
            if let url = CaskIconURL.faviconURL(for: cask.homepage),
               let image = await fetch(url) {
                cache(image: image, token: token)
                return image
            }

            // Tier 3: GitHub org avatar only (skip personal accounts — their avatars are faces, not app icons)
            if let owner = CaskIconURL.gitHubOwner(homepage: cask.homepage, downloadURL: cask.url),
               await isGitHubOrganization(owner: owner),
               let url = CaskIconURL.gitHubAvatarURL(for: owner),
               let image = await fetch(url) {
                cache(image: image, token: token)
                return image
            }

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
              let httpResponse = response as? HTTPURLResponse else {
            return (nil, false)
        }
        guard httpResponse.statusCode == 200,
              let image = NSImage(data: data),
              image.isValid else {
            return (nil, true)
        }
        return (image, true)
    }

    private func cache(image: NSImage, token: String, fromCaskKit: Bool = false) {
        memoryCache.setObject(image, forKey: token as NSString)
        saveToDisk(image: image, token: token)
        try? FileManager.default.removeItem(at: missMarkerPath(for: token))
        if fromCaskKit {
            // Terminal quality — never re-checked.
            try? FileManager.default.removeItem(at: fallbackMarkerPath(for: token))
        } else {
            // Fallback tier (App-Fair/favicon/avatar): upgrade-eligible.
            // mtime = now, so the first CaskKit re-check happens tomorrow —
            // CaskKit necessarily missed moments ago on this same chain run.
            try? Data().write(to: fallbackMarkerPath(for: token), options: .atomic)
        }
    }

    // MARK: - Fallback upgrade

    private func fallbackMarkerPath(for token: String) -> URL {
        Self.cacheDirectory.appendingPathComponent("\(token).fallback")
    }

    /// A disk-cached fallback icon is re-checked against CaskKit at most once
    /// per missRetryInterval — lazily, only when the cask is actually shown.
    /// A hit permanently replaces the cached icon and retires the marker.
    private func maybeUpgradeFallbackIcon(token: String) {
        let marker = fallbackMarkerPath(for: token)
        guard let mtime = try? FileManager.default
            .attributesOfItem(atPath: marker.path)[.modificationDate] as? Date,
            Date().timeIntervalSince(mtime) >= Self.missRetryInterval,
            !upgradeInFlight.contains(token) else {
            return
        }
        upgradeInFlight.insert(token)
        Task {
            for url in CaskIconURL.caskKitIconURLs(for: token) {
                let (image, _) = await downloadImage(from: url)
                if let image {
                    cache(image: image, token: token, fromCaskKit: true)
                    upgradeInFlight.remove(token)
                    return
                }
            }
            // Still not on CaskKit — reset the daily timer.
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: marker.path)
            upgradeInFlight.remove(token)
        }
    }

    /// One-time migration: icons cached before tier tracking existed get a
    /// backdated fallback marker, making them upgrade-eligible immediately.
    private nonisolated static func migrateUntieredCacheIfNeeded() {
        Task.detached(priority: .utility) {
            let dir = await Self.cacheDirectory
            let flag = dir.appendingPathComponent(".tier-migration-done")
            guard !FileManager.default.fileExists(atPath: flag.path) else { return }
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            let epoch = Date(timeIntervalSince1970: 0)
            for file in files where file.pathExtension == "png" {
                let token = file.deletingPathExtension().lastPathComponent
                let marker = dir.appendingPathComponent("\(token).fallback")
                guard !FileManager.default.fileExists(atPath: marker.path) else { continue }
                try? Data().write(to: marker, options: .atomic)
                try? FileManager.default.setAttributes(
                    [.modificationDate: epoch], ofItemAtPath: marker.path)
            }
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
            .attributesOfItem(atPath: path.path)[.modificationDate] as? Date else {
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
              image.isValid else {
            return nil
        }
        return image
    }

    private nonisolated func saveToDisk(image: NSImage, token: String) {
        Task.detached(priority: .utility) {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                return
            }
            let path = await Self.cacheDirectory.appendingPathComponent("\(token).png")
            try? pngData.write(to: path, options: .atomic)
        }
    }

    // MARK: - GitHub Organization Check

    /// Checks if a GitHub owner is an Organization (not a personal account).
    /// Uses HEAD request to github.com/orgs/{owner} — 302 = org, 404 = user.
    /// No API rate limits. Only definitive results are cached, so transient network failures won't permanently blacklist an owner.
    private func isGitHubOrganization(owner: String) async -> Bool {
        if let cached = ownerTypeCache[owner] {
            return cached
        }

        guard let isOrg = await checkGitHubOrgStatus(owner: owner) else {
            // Network error or unexpected status — don't cache, retry next time
            return false
        }
        ownerTypeCache[owner] = isOrg
        persistOwnerTypeCache()
        return isOrg
    }

    /// Returns true for org, false for user, nil for network error or unexpected status (don't cache)
    private func checkGitHubOrgStatus(owner: String) async -> Bool? {
        guard let url = URL(string: "https://github.com/orgs/\(owner)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await Self.noRedirectSession.data(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            return nil
        }
        switch httpResponse.statusCode {
        case 302: return true   // organization (redirects to org page)
        case 404: return false  // personal user
        default:  return nil    // unexpected — don't cache
        }
    }

    private func persistOwnerTypeCache() {
        let cache = ownerTypeCache
        let path = Self.ownerTypeCachePath
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(cache) else { return }
            try? data.write(to: path, options: .atomic)
        }
    }

    private static func loadOwnerTypeCache() -> [String: Bool] {
        guard let data = try? Data(contentsOf: ownerTypeCachePath),
              let cache = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return cache
    }
}

/// Prevents URLSession from following redirects so we can inspect the status code
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = NoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil) // Don't follow redirect
    }
}
