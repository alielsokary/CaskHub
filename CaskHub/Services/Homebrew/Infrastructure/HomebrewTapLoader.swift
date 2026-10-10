//
//  HomebrewTapLoader.swift
//  CaskHub
//

import Foundation

nonisolated struct HomebrewTap: Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let caskTokens: [String]

    var id: String {
        name
    }
}

nonisolated struct HomebrewTapSnapshot: Equatable, Sendable {
    let taps: [HomebrewTap]
    let casks: [Cask]
}

nonisolated struct HomebrewTapCommandResult: Equatable, Sendable {
    let succeeded: Bool
    let output: String
}

nonisolated protocol HomebrewTapManaging: Sendable {
    func load(from brewURL: URL?) async -> HomebrewTapSnapshot?
    func add(_ name: String, remote: String?, using brewURL: URL?) async -> HomebrewTapCommandResult
    func remove(_ name: String, using brewURL: URL?) async -> HomebrewTapCommandResult
    func update(using brewURL: URL?) async -> HomebrewTapCommandResult
}

nonisolated enum HomebrewTapName {
    static let excluded: Set<String> = ["homebrew/core", "homebrew/cask"]

    static func normalized(_ input: String) -> String? {
        var name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = name.range(of: "github.com/") {
            name = String(name[range.upperBound...])
        }
        if name.hasSuffix(".git") { name.removeLast(4) }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ isValidComponent($0) })
        else { return nil }
        let repository = parts[1].hasPrefix("homebrew-") ? parts[1].dropFirst("homebrew-".count) : parts[1]
        guard !repository.isEmpty else { return nil }
        return "\(parts[0])/\(repository)".lowercased()
    }

    static func isValidRemote(_ remote: String) -> Bool {
        let allowed = ["https://", "ssh://", "git://", "git@"]
        return allowed.contains { remote.hasPrefix($0) }
            && !remote.contains { $0.isWhitespace }
    }

    private static func isValidComponent(_ component: Substring) -> Bool {
        !component.isEmpty
            && !component.hasPrefix("-")
            && component.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) }
    }
}

nonisolated struct HomebrewTapLoader: HomebrewTapManaging {
    private static let environment = [
        "HOMEBREW_NO_AUTO_UPDATE": "1",
        "HOMEBREW_NO_ENV_HINTS": "1"
    ]
    private static let infoChunkSize = 100

    @concurrent
    func load(from brewURL: URL?) async -> HomebrewTapSnapshot? {
        guard let brewURL,
              let listing = ProcessCapture.capture(
                  brewURL, arguments: ["tap"], environment: Self.environment
              ),
              listing.status == 0
        else { return nil }
        let names = Self.tapNames(in: listing.output ?? "")
        guard !names.isEmpty else { return HomebrewTapSnapshot(taps: [], casks: []) }
        guard let info = ProcessCapture.capture(
            brewURL, arguments: ["tap-info", "--json"] + names, environment: Self.environment
        ),
            info.status == 0,
            let taps = Self.taps(in: info.output ?? "")
        else { return nil }
        let tokens = taps.flatMap(\.caskTokens)
        var casks: [Cask] = []
        for start in stride(from: 0, to: tokens.count, by: Self.infoChunkSize) {
            let chunk = Array(tokens[start ..< min(start + Self.infoChunkSize, tokens.count)])
            casks += Self.casks(for: chunk, brewURL: brewURL)
        }
        return HomebrewTapSnapshot(taps: taps, casks: casks)
    }

    @concurrent
    func add(_ name: String, remote: String?, using brewURL: URL?) async -> HomebrewTapCommandResult {
        guard let normalized = HomebrewTapName.normalized(name),
              remote.map(HomebrewTapName.isValidRemote) ?? true
        else {
            return HomebrewTapCommandResult(
                succeeded: false,
                output: String(localized: "Enter the tap as user/repo, with an https:// or ssh remote if it is not on GitHub.")
            )
        }
        return run(["tap", normalized] + (remote.map { [$0] } ?? []), brewURL: brewURL)
    }

    @concurrent
    func remove(_ name: String, using brewURL: URL?) async -> HomebrewTapCommandResult {
        guard let normalized = HomebrewTapName.normalized(name) else {
            return HomebrewTapCommandResult(succeeded: false, output: "")
        }
        return run(["untap", normalized], brewURL: brewURL)
    }

    @concurrent
    func update(using brewURL: URL?) async -> HomebrewTapCommandResult {
        run(["update"], brewURL: brewURL, environment: ["HOMEBREW_NO_ENV_HINTS": "1"])
    }

    static func tapNames(in output: String) -> [String] {
        output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !HomebrewTapName.excluded.contains($0) }
    }

    static func taps(in output: String) -> [HomebrewTap]? {
        guard let decoded = try? JSONDecoder().decode([TapInfo].self, from: Data(output.utf8))
        else { return nil }
        return decoded
            .filter { !HomebrewTapName.excluded.contains($0.name) }
            .map { HomebrewTap(name: $0.name, caskTokens: $0.caskTokens ?? []) }
            .sorted { $0.name < $1.name }
    }

    static func casks(in output: String) -> [Cask] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let decoded = try? decoder.decode(CaskInfoOutput.self, from: Data(output.utf8))
        else { return [] }
        return decoded.casks.compactMap(\.cask)
    }

    private static func casks(for tokens: [String], brewURL: URL) -> [Cask] {
        guard !tokens.isEmpty else { return [] }
        if let result = ProcessCapture.capture(
            brewURL,
            arguments: ["info", "--json=v2", "--cask"] + tokens,
            environment: environment
        ), result.status == 0 {
            return casks(in: result.output ?? "")
        }
        guard tokens.count > 1 else { return [] }
        let middle = tokens.count / 2
        return casks(for: Array(tokens[..<middle]), brewURL: brewURL)
            + casks(for: Array(tokens[middle...]), brewURL: brewURL)
    }

    private func run(
        _ arguments: [String],
        brewURL: URL?,
        environment: [String: String] = Self.environment
    ) -> HomebrewTapCommandResult {
        guard let brewURL,
              let result = ProcessCapture.capture(
                  brewURL, arguments: arguments, environment: environment, mergeStderr: true
              )
        else {
            return HomebrewTapCommandResult(
                succeeded: false,
                output: String(localized: "Homebrew could not be found.")
            )
        }
        return HomebrewTapCommandResult(
            succeeded: result.status == 0,
            output: (result.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private nonisolated struct TapInfo: Decodable {
    let name: String
    let caskTokens: [String]?

    private enum CodingKeys: String, CodingKey {
        case name
        case caskTokens = "cask_tokens"
    }
}

private nonisolated struct CaskInfoOutput: Decodable {
    struct Entry: Decodable {
        let cask: Cask?

        init(from decoder: Decoder) throws {
            cask = try? Cask(from: decoder)
        }
    }

    let casks: [Entry]
}
