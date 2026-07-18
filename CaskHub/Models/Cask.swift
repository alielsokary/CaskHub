//
//  Cask.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

struct ArtifactStanza: Codable, Hashable {
    let keys: Set<String>

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? {
            nil
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }

    init(from decoder: Decoder) throws {
        keys = Set((try? decoder.container(keyedBy: AnyKey.self))?
            .allKeys.map(\.stringValue) ?? [])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        for key in keys {
            try container.encode(true, forKey: AnyKey(stringValue: key)!)
        }
    }
}

struct Cask: Codable, Identifiable, Hashable {
    let token: String
    let fullToken: String?
    let tap: String?
    let name: [String]
    let desc: String?
    let homepage: String
    let url: String?
    let version: String
    let bundleVersion: String?
    let bundleShortVersion: String?
    let outdated: Bool
    let deprecated: Bool
    let disabled: Bool
    let autoUpdates: Bool?
    var artifacts: [ArtifactStanza]?

    var id: String {
        token
    }

    var isCLI: Bool {
        guard let artifacts, !artifacts.isEmpty else { return false }
        return artifacts.contains { !$0.keys.isDisjoint(with: ["binary", "stageOnly", "stage_only"]) }
            && !artifacts.contains { !$0.keys.isDisjoint(with: ["app", "suite", "pkg"]) }
    }

    var displayName: String {
        name.first ?? token
    }

    var displayVersion: String {
        let base = version.split(separator: ",", maxSplits: 1).first.map(String.init) ?? version

        let numeric = String(base.prefix(while: { $0.isNumber || $0 == "." }))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return numeric.isEmpty ? base : numeric
    }

    func metaLine(downloads: String?) -> String {
        var parts: [String] = []
        if let downloads { parts.append("↓ \(downloads)") }
        parts.append("v\(displayVersion)")
        return parts.joined(separator: " · ")
    }
}

#if DEBUG
extension Cask {
    static func preview(
        token: String,
        name: String? = nil,
        desc: String? = nil,
        version: String = "1.0",
        deprecated: Bool = false,
        disabled: Bool = false,
        autoUpdates: Bool? = nil
    ) -> Cask {
        Cask(
            token: token,
            fullToken: nil,
            tap: nil,
            name: [name ?? token],
            desc: desc,
            homepage: "https://example.com",
            url: nil,
            version: version,
            bundleVersion: nil,
            bundleShortVersion: nil,
            outdated: false,
            deprecated: deprecated,
            disabled: disabled,
            autoUpdates: autoUpdates
        )
    }
}
#endif
