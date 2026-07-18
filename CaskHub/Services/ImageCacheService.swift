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

    private static let missRetryInterval: TimeInterval = 24 * 60 * 60

    private static let cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("CaskHub/icons", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
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

        if let cached = memoryCache.object(forKey: token as NSString) {
            return cached
        }

        if cask.isCLI {
            purgeStaleCLIIcon(token: token)
        }

        if let diskImage = loadFromDisk(token: token) {
            memoryCache.setObject(diskImage, forKey: token as NSString)
            maybeUpgradeFallbackIcon(token: token)
            return diskImage
        }

        if hasRecentMiss(token: token) {
            return nil
        }

        if let existing = inFlightTasks[token] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            var sawHTTPResponse = false
            func fetch(_ url: URL) async -> NSImage? {
                let (image, responded) = await self.downloadImage(from: url)
                sawHTTPResponse = sawHTTPResponse || responded
                return image
            }

            for url in CaskIconURL.caskFlowIconURLs(for: token) {
                if let image = await fetch(url) {
                    cache(image: image, token: token, fromCaskFlow: true)
                    return image
                }
            }

            if !cask.isCLI,
               let url = CaskIconURL.appFairIconURL(for: token),
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

    func clearCache() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: Self.cacheDirectory)
        try? FileManager.default.createDirectory(
            at: Self.cacheDirectory, withIntermediateDirectories: true
        )
    }

    // MARK: - Private

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
            try? FileManager.default.removeItem(at: fallbackMarkerPath(for: token))
        } else {
            try? Data().write(to: fallbackMarkerPath(for: token), options: .atomic)
        }
    }

    // MARK: - CLI cutover purge

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
        let urlCache = session.configuration.urlCache ?? .shared
        for url in CaskIconURL.caskFlowIconURLs(for: token) {
            urlCache.removeCachedResponse(for: URLRequest(url: url))
        }
    }

    // MARK: - Fallback upgrade

    private func fallbackMarkerPath(for token: String) -> URL {
        Self.cacheDirectory.appendingPathComponent("\(token).fallback")
    }

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
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: marker.path
            )
            upgradeInFlight.remove(token)
        }
    }

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
