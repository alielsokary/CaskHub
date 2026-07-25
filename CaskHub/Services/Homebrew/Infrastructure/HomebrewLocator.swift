//
//  HomebrewLocator.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated enum HomebrewLocator {
    static let customPrefixKey = "customBrewPrefix"

    /// Machine architecture, not build architecture: `hw.optional.arm64`
    /// remains accurate when CaskHub runs under Rosetta.
    static let isAppleSilicon: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return value == 1
    }()

    static func caskroomURL(
        customPrefix: String? = nil,
        fileManager: FileManager
    ) -> URL? {
        if let customPrefix, !customPrefix.isEmpty {
            let configured = URL(fileURLWithPath: customPrefix)
                .appendingPathComponent("Caskroom")
            if fileManager.fileExists(atPath: configured.path) {
                return configured
            }
        }
        return prefixCandidates("Caskroom").first {
            fileManager.fileExists(atPath: $0.path)
        }
    }

    static func binaryDirectories(fileManager: FileManager) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        return prefixCandidates("bin") + [
            home.appendingPathComponent(".local/bin"),
            home.appendingPathComponent("bin")
        ]
    }

    /// Accepts the brew binary, a Homebrew prefix, or its `bin` folder.
    static func prefix(
        from selection: URL,
        fileManager: FileManager = .default
    ) -> String? {
        if selection.lastPathComponent == "brew",
           fileManager.isExecutableFile(atPath: selection.path) {
            return selection.deletingLastPathComponent()
                .deletingLastPathComponent().path
        }
        if fileManager.isExecutableFile(
            atPath: selection.appendingPathComponent("bin/brew").path
        ) {
            return selection.path
        }
        if fileManager.isExecutableFile(
            atPath: selection.appendingPathComponent("brew").path
        ) {
            return selection.deletingLastPathComponent().path
        }
        return nil
    }

    static func brewBinaryURL(fileManager: FileManager = .default) -> URL? {
        prefixCandidates("bin/brew").first {
            fileManager.isExecutableFile(atPath: $0.path)
        }
    }

    private static func prefixCandidates(_ relativePath: String) -> [URL] {
        var candidates: [URL] = []
        if let custom = UserDefaults.standard.string(forKey: customPrefixKey),
           !custom.isEmpty {
            candidates.append(
                URL(fileURLWithPath: custom).appendingPathComponent(relativePath)
            )
        }
        if let prefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"],
           !prefix.isEmpty {
            candidates.append(
                URL(fileURLWithPath: prefix).appendingPathComponent(relativePath)
            )
        }
        let standardPrefixes = isAppleSilicon
            ? ["/opt/homebrew", "/usr/local"]
            : ["/usr/local", "/opt/homebrew"]
        candidates.append(contentsOf: standardPrefixes.map {
            URL(fileURLWithPath: $0).appendingPathComponent(relativePath)
        })
        return candidates
    }
}
