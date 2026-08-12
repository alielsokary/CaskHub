//
//  HomebrewLocator.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated enum HomebrewLocator {
    static let customPrefixKey = "customBrewPrefix"
    static let appleSiliconPrefix = "/opt/homebrew"
    static let intelPrefix = "/usr/local"

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
        let prefix = customPrefix.flatMap(compatiblePrefix)
            ?? (customPrefix == nil ? selectedPrefix() : nil)
        guard let prefix else { return nil }
        let caskroom = prefix.appendingPathComponent("Caskroom")
        return fileManager.fileExists(atPath: caskroom.path) ? caskroom : nil
    }

    static func binaryDirectories(fileManager: FileManager) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        let homebrewBin = selectedPrefix()?.appendingPathComponent("bin")
        return [homebrewBin].compactMap { $0 } + [
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
        guard let prefix = selectedPrefix() else { return nil }
        let brewURL = prefix.appendingPathComponent("bin/brew")
        guard fileManager.isExecutableFile(atPath: brewURL.path),
              isCompatible(brewURL: brewURL)
        else { return nil }
        return brewURL
    }

    static func isCompatible(
        brewURL: URL,
        machineIsAppleSilicon: Bool = isAppleSilicon
    ) -> Bool {
        let standardized = brewURL.standardizedFileURL.path
        let resolved = brewURL.resolvingSymlinksInPath().standardizedFileURL.path
        if standardized == "\(appleSiliconPrefix)/bin/brew"
            || resolved.hasPrefix("\(appleSiliconPrefix)/Homebrew/") {
            return machineIsAppleSilicon
        }
        if standardized == "\(intelPrefix)/bin/brew"
            || resolved.hasPrefix("\(intelPrefix)/Homebrew/") {
            return !machineIsAppleSilicon
        }
        return true
    }

    private static func selectedPrefix() -> URL? {
        if let custom = UserDefaults.standard.string(forKey: customPrefixKey),
           !custom.isEmpty {
            return compatiblePrefix(custom)
        }
        if let prefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"],
           !prefix.isEmpty {
            return compatiblePrefix(prefix)
        }
        return URL(fileURLWithPath: isAppleSilicon ? appleSiliconPrefix : intelPrefix)
    }

    private static func compatiblePrefix(_ path: String) -> URL? {
        let prefix = URL(fileURLWithPath: path)
        guard !path.isEmpty,
              isCompatible(brewURL: prefix.appendingPathComponent("bin/brew"))
        else { return nil }
        return prefix
    }
}
