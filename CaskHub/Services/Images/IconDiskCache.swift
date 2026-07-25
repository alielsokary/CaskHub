//
//  IconDiskCache.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Foundation

actor IconDiskCache {
    static let shared = IconDiskCache(directory: defaultDirectory)

    static let defaultDirectory: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CaskHub/icons", isDirectory: true)
    }()

    private let directory: URL
    private var generation: UInt64 = 0

    init(directory: URL) {
        self.directory = directory
    }

    func currentGeneration() -> UInt64 {
        generation
    }

    func isCurrent(_ expectedGeneration: UInt64) -> Bool {
        generation == expectedGeneration
    }

    func loadData(token: String) -> Data? {
        try? Data(contentsOf: path(token: token, fileExtension: "png"))
    }

    @discardableResult
    func store(
        _ data: Data,
        token: String,
        generation expectedGeneration: UInt64,
        fromCaskFlow: Bool
    ) throws -> Bool {
        guard generation == expectedGeneration else { return false }
        try ensureDirectory()
        try writeAtomically(data, to: path(token: token, fileExtension: "png"))
        try? FileManager.default.removeItem(at: path(token: token, fileExtension: "miss"))
        if fromCaskFlow {
            try? FileManager.default.removeItem(
                at: path(token: token, fileExtension: "fallback")
            )
        } else {
            try writeAtomically(
                Data(),
                to: path(token: token, fileExtension: "fallback")
            )
        }
        return true
    }

    func hasRecentMiss(token: String, retryInterval: TimeInterval) -> Bool {
        guard let modified = modificationDate(
            for: path(token: token, fileExtension: "miss")
        ) else {
            return false
        }
        return Date().timeIntervalSince(modified) < retryInterval
    }

    func recordMiss(token: String, generation expectedGeneration: UInt64) throws {
        guard generation == expectedGeneration else { return }
        try ensureDirectory()
        try writeAtomically(
            Data(),
            to: path(token: token, fileExtension: "miss")
        )
    }

    func fallbackNeedsUpgrade(token: String, retryInterval: TimeInterval) -> Bool {
        guard let modified = modificationDate(
            for: path(token: token, fileExtension: "fallback")
        ) else {
            return false
        }
        return Date().timeIntervalSince(modified) >= retryInterval
    }

    func touchFallback(token: String, generation expectedGeneration: UInt64) throws {
        guard generation == expectedGeneration else { return }
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: path(token: token, fileExtension: "fallback").path
        )
    }

    func purgeStaleCLIIcon(token: String, before cutover: Date) -> Bool {
        let iconPath = path(token: token, fileExtension: "png")
        guard let modified = modificationDate(for: iconPath), modified < cutover else {
            return false
        }
        try? FileManager.default.removeItem(at: iconPath)
        try? FileManager.default.removeItem(
            at: path(token: token, fileExtension: "fallback")
        )
        return true
    }

    func clear() throws {
        generation &+= 1
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try ensureDirectory()
    }

    func purgeGeneratedIconsIfNeeded() throws {
        try ensureDirectory()
        let flag = directory.appendingPathComponent(".generated-purge-done")
        guard !FileManager.default.fileExists(atPath: flag.path) else { return }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for marker in files where marker.pathExtension == "fallback" {
            let token = marker.deletingPathExtension().lastPathComponent
            try? FileManager.default.removeItem(
                at: path(token: token, fileExtension: "png")
            )
            try? FileManager.default.removeItem(at: marker)
        }
        try? FileManager.default.removeItem(
            at: directory.deletingLastPathComponent()
                .appendingPathComponent("github_owner_types.json")
        )
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(".tier-migration-done")
        )
        try writeAtomically(Data(), to: flag)
    }

    func fileNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // The directory may also be removed outside the app. Repair it once
            // before surfacing a persistent filesystem failure.
            try ensureDirectory()
            try data.write(to: url, options: .atomic)
        }
    }

    private func path(token: String, fileExtension pathExtension: String) -> URL {
        directory.appendingPathComponent("\(token).\(pathExtension)")
    }

    private func modificationDate(for url: URL) -> Date? {
        try? FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
