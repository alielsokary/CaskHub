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

    /// Third-party taps only. A tap whose second argument isn't a secure https remote is never added:
    /// dropping the remote would make brew clone a different repository under the same name.
    static func taps(in contents: String) -> BrewfileTaps {
        var seen: Set<String> = []
        var taps = BrewfileTaps()
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let match = line.firstMatch(
                of: /^\s*tap\s+["']([^"']+)["'](?:\s*,\s*["']([^"']+)["'])?/
            ),
                case let .success(parsed) = TapAddInput.parse(String(match.1)),
                parsed.caskToken == nil,
                seen.insert(parsed.tapName).inserted
            else { continue }
            let remote = match.2.map { TapAddInput.secureRemote(String($0)) }
            if case .some(.none) = remote {
                taps.unsupported.append(parsed.tapName)
            } else {
                taps.toAdd.append(TapAddRequest(tapName: parsed.tapName, remoteURL: remote ?? nil, caskToken: nil))
            }
        }
        return taps
    }

    static func contents(forCaskReferences references: [String]) -> String {
        let taps = Set(references.compactMap(CaskReference.tap(of:))).sorted()
        return taps.map { "tap \"\($0)\"\n" }.joined()
            + references.sorted().map { "cask \"\($0)\"\n" }.joined()
    }
}

nonisolated struct BrewfileTaps: Equatable {
    var toAdd: [TapAddRequest] = []
    /// Taps with a remote CaskHub won't pass to brew; their casks are skipped too.
    var unsupported: [String] = []
}
