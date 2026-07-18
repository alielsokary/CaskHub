//
//  Cask.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

struct ArtifactStanza: Codable, Hashable {
    let keys: Set<String>
    let appNames: [String]

    init(keys: Set<String>, appNames: [String] = []) {
        self.keys = keys
        self.appNames = appNames
    }

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

    /// An `app` array element: a bundle name, or a `{"target": …}` rename dict.
    /// Lenient so one odd entry can't zero out the whole array.
    private struct AppEntry: Decodable {
        let name: String?
        let target: String?

        init(from decoder: Decoder) throws {
            if let string = try? decoder.singleValueContainer().decode(String.self) {
                name = string
                target = nil
                return
            }
            name = nil
            target = (try? decoder.container(keyedBy: AnyKey.self))
                .flatMap { try? $0.decode(String.self, forKey: AnyKey(stringValue: "target")!) }
        }
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: AnyKey.self) else {
            keys = []
            appNames = []
            return
        }
        keys = Set(container.allKeys.map(\.stringValue))

        let entries = AnyKey(stringValue: "app")
            .flatMap { try? container.decode([AppEntry].self, forKey: $0) } ?? []
        var names: [String] = []
        for entry in entries {
            if let name = entry.name {
                names.append(name)
            } else if let target = entry.target, !names.isEmpty {
                // `app "X.app", target: "Y.app"` — the on-disk bundle is the target.
                names[names.count - 1] = URL(fileURLWithPath: target).lastPathComponent
            }
        }
        appNames = names
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        for key in keys {
            if key == "app", !appNames.isEmpty {
                try container.encode(appNames, forKey: AnyKey(stringValue: key)!)
            } else {
                try container.encode(true, forKey: AnyKey(stringValue: key)!)
            }
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

    /// Bundle names this cask installs into /Applications (e.g. "Google Chrome.app").
    var appArtifactNames: [String] {
        artifacts?.flatMap(\.appNames) ?? []
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
