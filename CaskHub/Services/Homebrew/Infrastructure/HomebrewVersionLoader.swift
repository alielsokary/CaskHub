//
//  HomebrewVersionLoader.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated enum ProcessCapture {
    /// One pipe serves both streams: a single read cannot deadlock on a full sibling buffer.
    static func capture(
        _ executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        mergeStderr: Bool = false
    ) -> (status: Int32, output: String?)? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment
                .merging(environment) { _, override in override }
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = mergeStderr ? pipe : FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8))
    }
}

nonisolated struct HomebrewVersionLoader: Sendable {
    @concurrent
    func load(from brewURL: URL?) async -> String? {
        guard let brewURL,
              let result = ProcessCapture.capture(brewURL, arguments: ["--version"]),
              result.status == 0,
              let firstLine = result.output?.split(separator: "\n").first
        else { return nil }
        return firstLine.split(separator: " ").last.map(String.init)
    }
}

nonisolated struct HomebrewOutdatedLoader: Sendable {
    /// Homebrew's own answer for every installed cask, or nil when Homebrew cannot answer.
    @concurrent
    func load(from brewURL: URL?, userRequested: Bool) async -> HomebrewOutdatedReport? {
        guard let brewURL else { return nil }
        // `brew info` never auto-updates, so its answer is only as fresh as Homebrew's last update.
        // A user's refresh runs `brew update`, as Terminal does; automatic checks run
        // `brew update-if-needed`, which follows the user's own auto-update settings.
        // A failed update is not fatal: the read below still answers from the data Homebrew has.
        _ = ProcessCapture.capture(brewURL, arguments: userRequested ? ["update", "--quiet"] : ["update-if-needed"])
        guard let result = ProcessCapture.capture(
            brewURL,
            arguments: ["info", "--installed", "--cask", "--json=v2"],
            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"]
        ) else { return nil }
        return Self.report(in: result.output ?? "")
    }

    static func report(in output: String) -> HomebrewOutdatedReport? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let decoded = try? decoder.decode(InstalledInfoOutput.self, from: Data(output.utf8)) else { return nil }
        let pinned = Set(decoded.casks.filter { $0.pinned == true }.map(\.token))
        return HomebrewOutdatedReport(
            upgradable: Set(decoded.casks.filter { $0.outdated == true }.map(\.token)).subtracting(pinned),
            pinned: pinned,
            installedCasks: decoded.casks.compactMap(\.cask)
        )
    }
}

/// `brew info --installed --cask --json=v2`: the API's cask shape plus Homebrew's local `outdated` and `pinned`.
private nonisolated struct InstalledInfoOutput: Decodable {
    let casks: [InstalledCaskInfo]
}

private nonisolated struct InstalledCaskInfo: Decodable {
    let token: String
    let outdated: Bool?
    let pinned: Bool?
    /// Nil only without a version to upgrade to, or when the cask is disabled.
    let cask: Cask?

    private enum CodingKeys: String, CodingKey {
        case token, outdated, pinned, tap, name, version, autoUpdates, disabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        outdated = try? container.decode(Bool.self, forKey: .outdated)
        pinned = try? container.decode(Bool.self, forKey: .pinned)
        if let cask = try? Cask(from: decoder) {
            self.cask = cask
            return
        }
        // A tap can leave out fields the catalog model requires, such as `homepage`;
        // Homebrew's version still gives the cask an update target.
        guard let version = try? container.decode(String.self, forKey: .version), !version.isEmpty,
              (try? container.decode(Bool.self, forKey: .disabled)) != true
        else {
            cask = nil
            return
        }
        cask = Cask.minimal(
            token: token,
            tap: try? container.decode(String.self, forKey: .tap),
            name: (try? container.decode([String].self, forKey: .name))?.first ?? token,
            version: version,
            autoUpdates: try? container.decode(Bool.self, forKey: .autoUpdates)
        )
    }
}

extension Cask {
    /// A cask described by only the fields Homebrew reports for every installed token.
    static func minimal(token: String, tap: String?, name: String, version: String, autoUpdates: Bool?) -> Cask {
        Cask(
            token: token,
            fullToken: nil,
            tap: tap,
            name: [name],
            desc: nil,
            homepage: "",
            url: nil,
            sha256: nil,
            version: version,
            bundleVersion: nil,
            bundleShortVersion: nil,
            outdated: false,
            deprecated: false,
            disabled: false,
            autoUpdates: autoUpdates,
            variations: nil,
            supportedPlatforms: nil,
            conflictsWith: nil,
            deprecationDate: nil,
            deprecationReason: nil,
            deprecationReplacementCask: nil,
            deprecationReplacementFormula: nil,
            disableDate: nil,
            disableReason: nil,
            disableReplacementCask: nil,
            disableReplacementFormula: nil
        )
    }
}
