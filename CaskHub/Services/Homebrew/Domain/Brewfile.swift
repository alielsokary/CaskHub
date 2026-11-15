//
//  Brewfile.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/08/2026.
//

import Foundation

/// Reads and writes the `tap` and `cask` entries of a `brew bundle` Brewfile.
/// Other entry kinds (`brew`, `mas`, comments) are left alone.
nonisolated enum Brewfile {
    static func caskTokens(in contents: String) -> [String] {
        var seen: Set<String> = []
        return contents.split(whereSeparator: \.isNewline).compactMap { line in
            guard let match = line.firstMatch(
                of: /^\s*cask\s+["']([^"']+)["']/
            ) else { return nil }
            let token = String(match.1)
            return seen.insert(token).inserted ? token : nil
        }
    }

    /// Third-party taps only; an optional second argument is kept when it is an http(s) URL.
    static func taps(in contents: String) -> [TapAddRequest] {
        var seen: Set<String> = []
        return contents.split(whereSeparator: \.isNewline).compactMap { line in
            guard let match = line.firstMatch(
                of: /^\s*tap\s+["']([^"']+)["'](?:\s*,\s*["']([^"']+)["'])?/
            ),
                case let .success(parsed) = TapAddInput.parse(String(match.1)),
                parsed.caskToken == nil,
                seen.insert(parsed.tapName).inserted
            else { return nil }
            return TapAddRequest(tapName: parsed.tapName, remoteURL: match.2.flatMap { URL.web(String($0)) }, caskToken: nil)
        }
    }

    static func contents(forCaskReferences references: [String]) -> String {
        let taps = Set(references.compactMap(CaskReference.tap(of:))).sorted()
        return taps.map { "tap \"\($0)\"\n" }.joined()
            + references.sorted().map { "cask \"\($0)\"\n" }.joined()
    }
}
