//
//  MaintenanceProbe.swift
//  CaskHub
//
//  Created by Ali Elsokary on 19/08/2026.
//

import Foundation

nonisolated struct BrewProbeResult: Equatable, Sendable {
    let exitCode: Int32
    let output: String
}

nonisolated struct CachedInstaller: Equatable, Sendable, Identifiable {
    let name: String
    let bytes: Int64

    var id: String { name }
}

nonisolated protocol MaintenanceProbing: Sendable {
    func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]?
    ) async -> BrewProbeResult?
    func directorySize(at url: URL) async -> Int64
    func removeDirectoryContents(at url: URL) async -> Bool
    func cachedInstallers(at cacheURL: URL) async -> [CachedInstaller]
}

extension MaintenanceProbing {
    func run(_ executable: URL, arguments: [String]) async -> BrewProbeResult? {
        await run(executable, arguments: arguments, environment: nil)
    }
}

nonisolated struct SystemMaintenanceProbe: MaintenanceProbing {
    @concurrent
    func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]?
    ) async -> BrewProbeResult? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment
                .merging(environment) { _, override in override }
        }
        // One pipe for both streams: a single read cannot deadlock on a full
        // sibling buffer, and callers treat the output as one transcript anyway.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return BrewProbeResult(
            exitCode: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }

    @concurrent
    func directorySize(at url: URL) async -> Int64 {
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys)
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    /// Brew's cache keeps every payload hash-named in `downloads/` and indexes
    /// it with readable `token--version.ext` symlinks: casks under `Cask/`,
    /// formula bottles at the cache root. Resolving each link pairs the
    /// readable name with the real payload's size.
    @concurrent
    func cachedInstallers(at cacheURL: URL) async -> [CachedInstaller] {
        var installers: [CachedInstaller] = []
        for directory in [cacheURL.appendingPathComponent("Cask"), cacheURL] {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey]
            ) else { continue }
            for entry in entries
                where entry.pathExtension != "json"
                && !entry.lastPathComponent.contains("bottle_manifest") {
                guard let target = resolvedTarget(of: entry),
                      let targetValues = try? target.resourceValues(
                          forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
                      )
                else { continue }
                installers.append(CachedInstaller(
                    name: entry.lastPathComponent,
                    bytes: Int64(targetValues.totalFileAllocatedSize ?? targetValues.fileSize ?? 0)
                ))
            }
        }
        return installers.sorted { lhs, rhs in
            lhs.bytes != rhs.bytes ? lhs.bytes > rhs.bytes : lhs.name < rhs.name
        }
    }

    private func resolvedTarget(of entry: URL) -> URL? {
        guard let values = try? entry.resourceValues(
            forKeys: [.isSymbolicLinkKey, .isRegularFileKey]
        ) else { return nil }
        if values.isSymbolicLink == true {
            return entry.resolvingSymlinksInPath()
        }
        guard values.isRegularFile == true,
              let alias = try? URL(
                  resolvingAliasFileAt: entry,
                  options: [.withoutUI, .withoutMounting]
              ),
              alias.lastPathComponent != entry.lastPathComponent
        else { return nil }
        return alias
    }

    @concurrent
    func removeDirectoryContents(at url: URL) async -> Bool {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return false }
        var succeeded = true
        for entry in entries {
            do {
                try fileManager.removeItem(at: entry)
            } catch {
                succeeded = false
            }
        }
        return succeeded
    }
}
