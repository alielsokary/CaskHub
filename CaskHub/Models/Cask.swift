//
//  Cask.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

/// One `artifacts` stanza from the brew API — heterogeneous single-key
/// objects ({"app": [...]}, {"binary": [...]}); only the keys matter here.
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
        // Lenient: a malformed stanza must not sink the whole catalog decode.
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
    let installed: String?
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

    /// Ships a command-line `binary` (or a `stage_only` payload like sqlcl)
    /// and nothing GUI (no app/suite/pkg). The binary/stage requirement keeps
    /// installer-app GUI casks (autodesk-fusion, logi-options+) off the CLI
    /// treatment; pkg-based CLIs (git-credential-manager, ibm-cloud-cli)
    /// stay non-CLI and keep their real icons.
    ///
    /// Drives only the placeholder: CLI casks show a terminal tile instead
    /// of the window glyph. Which CLI casks get real icons anyway (Android
    /// SDK tools, tuist, conda family) is CaskFlow's call — whatever its
    /// icons branch serves wins over the tile.
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

    var homepageDomain: String? {
        URL(string: homepage)?.host
    }

    /// "↓ 1.2M · v125.0" — the downloads part is omitted when unknown.
    func metaLine(downloads: String?) -> String {
        var parts: [String] = []
        if let downloads { parts.append("↓ \(downloads)") }
        parts.append("v\(displayVersion)")
        return parts.joined(separator: " · ")
    }
}
