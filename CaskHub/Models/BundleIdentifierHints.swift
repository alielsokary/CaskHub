//
//  BundleIdentifierHints.swift
//  CaskHub
//
//  Created by Ali Elsokary on 27/11/2026.
//

import Foundation

/// Bundle identifiers named by a cask's zap and uninstall paths, such as
/// `~/Library/Preferences/com.example.app.plist`.
nonisolated struct BundleIdentifierHints: Decodable {
    let identifiers: [String]

    private enum CodingKeys: String, CodingKey {
        case zap, uninstall
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifiers = [CodingKeys.zap, .uninstall]
            .flatMap { (try? container.decode(StringLeaves.self, forKey: $0))?.values ?? [] }
            .compactMap(Self.identifier(in:))
    }

    static func identifier(in path: String) -> String? {
        guard var name = path.split(separator: "/").last.map(String.init) else { return nil }
        for suffix in [".plist", ".savedState", ".binarycookies"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }),
              !name.lowercased().hasPrefix("com.apple.")
        else { return nil }
        return name
    }
}

/// Every string in a JSON value, however deeply nested.
private nonisolated struct StringLeaves: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            values = [string]
        } else if let array = try? container.decode([StringLeaves].self) {
            values = array.flatMap(\.values)
        } else if let object = try? container.decode([String: StringLeaves].self) {
            values = object.values.flatMap(\.values)
        } else {
            values = []
        }
    }
}

extension Cask {
    var bundleIdentifierHints: [String] {
        artifacts?.flatMap(\.bundleIdentifierHints) ?? []
    }
}
