//
//  Brewfile.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/08/2026.
//

import Foundation

/// Reads and writes the `cask` entries of a `brew bundle` Brewfile.
/// Other entry kinds (`tap`, `brew`, `mas`, comments) are left alone.
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

    static func contents(forCaskTokens tokens: [String]) -> String {
        tokens.sorted().map { "cask \"\($0)\"\n" }.joined()
    }
}
