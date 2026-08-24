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

nonisolated enum BrewDoctorEnvironment {
    /// GUI apps get a sanitized PATH; front-load brew's bin and sbin so
    /// `brew doctor` matches a terminal run instead of raising PATH advisories.
    static func make(brewURL: URL) -> [String: String] {
        let binDir = brewURL.deletingLastPathComponent()
        let sbinDir = binDir.deletingLastPathComponent().appendingPathComponent("sbin")
        let currentPath = ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return ["PATH": "\(binDir.path):\(sbinDir.path):\(currentPath)"]
    }
}

nonisolated enum LatestReleaseChecker {
    @concurrent
    static func latestTag(owner: String, repo: String) async -> String? {
        guard let url = URL(
            string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        ) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        struct Release: Decodable {
            let tagName: String
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(Release.self, from: data))?.tagName
    }
}

nonisolated struct SystemMaintenanceProbe: MaintenanceProbing {
    @concurrent
    func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]?
    ) async -> BrewProbeResult? {
        await SystemHomebrewCommandExecutor.acquireGlobalTurn()
        let result = ProcessCapture.capture(
            executable,
            arguments: arguments,
            environment: environment,
            mergeStderr: true
        )
        await SystemHomebrewCommandExecutor.releaseGlobalTurn()
        guard let result else { return nil }
        return BrewProbeResult(exitCode: result.status, output: result.output ?? "")
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

    /// Payloads are hash-named in `downloads/`; readable `token--version.ext`
    /// symlinks index them from `Cask/` (casks) and the cache root (bottles).
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
