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
    private let session: URLSession
    private var ownerTypeCache: [String: Bool] = [:] // owner -> isOrg

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
    }

    func image(for cask: Cask) async -> NSImage? {
        let token = cask.token

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: token as NSString) {
            return cached
        }

        // 2. Disk cache
        if let diskImage = loadFromDisk(token: token) {
            memoryCache.setObject(diskImage, forKey: token as NSString)
            return diskImage
        }

        // 3. Coalesce in-flight requests
        if let existing = inFlightTasks[token] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            // Tier 1: App-Fair app icon (highest quality, actual macOS app icons)
            if let url = CaskIconURL.appIconURL(for: token),
               let image = await downloadImage(from: url) {
                cache(image: image, token: token)
                return image
            }

            // Tier 2: Homepage favicon via icon.horse (best for apps with dedicated websites)
            if let url = CaskIconURL.faviconURL(for: cask.homepage),
               let image = await downloadImage(from: url) {
                cache(image: image, token: token)
                return image
            }

            // Tier 3: GitHub org avatar only (skip personal accounts — their avatars are faces, not app icons)
            if let owner = CaskIconURL.gitHubOwner(homepage: cask.homepage, downloadURL: cask.url),
               await isGitHubOrganization(owner: owner),
               let url = CaskIconURL.gitHubAvatarURL(for: owner),
               let image = await downloadImage(from: url) {
                cache(image: image, token: token)
                return image
            }

            return nil
        }

        inFlightTasks[token] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: token)
        return result
    }

    // MARK: - Private

    private func downloadImage(from url: URL) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let image = NSImage(data: data),
              image.isValid else {
            return nil
        }
        return image
    }

    private func cache(image: NSImage, token: String) {
        memoryCache.setObject(image, forKey: token as NSString)
        saveToDisk(image: image, token: token)
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
