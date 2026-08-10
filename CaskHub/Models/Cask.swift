//
//  Cask.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

nonisolated struct ArtifactStanza: Decodable, Hashable {
    let keys: Set<String>
    let appNames: [String]
    let binaryNames: [String]
    let packageIdentifiers: [String]
    let deletedAppNames: [String]
    let applicationBundleIdentifiers: [String]

    /// Raw source paths of `binary` entries (e.g. a path inside the .app bundle).
    /// Needed to verify a bundle actually contains what the cask declares.
    let binarySourcePaths: [String]

    init(
        keys: Set<String>,
        appNames: [String] = [],
        binaryNames: [String] = [],
        binarySourcePaths: [String] = [],
        packageIdentifiers: [String] = [],
        deletedAppNames: [String] = [],
        applicationBundleIdentifiers: [String] = []
    ) {
        self.keys = keys
        self.appNames = appNames
        self.binaryNames = binaryNames
        self.binarySourcePaths = binarySourcePaths
        self.packageIdentifiers = packageIdentifiers
        self.deletedAppNames = deletedAppNames
        self.applicationBundleIdentifiers = applicationBundleIdentifiers
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

    private struct UninstallEntry: Decodable {
        let packageIdentifiers: [String]
        let deletedPaths: [String]
        let applicationBundleIdentifiers: [String]

        init(from decoder: Decoder) throws {
            guard let container = try? decoder.container(keyedBy: AnyKey.self) else {
                packageIdentifiers = []
                deletedPaths = []
                applicationBundleIdentifiers = []
                return
            }
            packageIdentifiers = Self.strings(in: container, key: "pkgutil")
            deletedPaths = Self.strings(in: container, key: "delete")
            applicationBundleIdentifiers = Self.strings(in: container, key: "quit")
        }

        private static func strings(
            in container: KeyedDecodingContainer<AnyKey>, key: String
        ) -> [String] {
            guard let codingKey = AnyKey(stringValue: key) else { return [] }
            if let value = try? container.decode(String.self, forKey: codingKey) {
                return [value]
            }
            return (try? container.decode([String].self, forKey: codingKey)) ?? []
        }
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: AnyKey.self) else {
            keys = []
            appNames = []
            binaryNames = []
            binarySourcePaths = []
            packageIdentifiers = []
            deletedAppNames = []
            applicationBundleIdentifiers = []
            return
        }
        keys = Set(container.allKeys.map(\.stringValue))
        appNames = Self.artifactNames(in: container, key: "app")
        binaryNames = Self.artifactNames(in: container, key: "binary")
        binarySourcePaths = (AnyKey(stringValue: "binary")
            .flatMap { try? container.decode([AppEntry].self, forKey: $0) } ?? [])
            .compactMap(\.name)
            .filter { $0.contains("/") }
        let uninstallEntries = (AnyKey(stringValue: "uninstall")
            .flatMap { try? container.decode([UninstallEntry].self, forKey: $0) } ?? [])
        packageIdentifiers = uninstallEntries.flatMap(\.packageIdentifiers)
        applicationBundleIdentifiers = uninstallEntries
            .flatMap(\.applicationBundleIdentifiers)
        deletedAppNames = uninstallEntries
            .flatMap(\.deletedPaths)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .filter { $0.hasSuffix(".app") }
    }

    /// Entries can be names or staged paths, with `{"target": …}` rename dicts
    /// following the entry they rename — the on-disk name is the target's basename.
    private static func artifactNames(
        in container: KeyedDecodingContainer<AnyKey>, key: String
    ) -> [String] {
        let entries = AnyKey(stringValue: key)
            .flatMap { try? container.decode([AppEntry].self, forKey: $0) } ?? []
        var names: [String] = []
        for entry in entries {
            if let name = entry.name {
                names.append(URL(fileURLWithPath: name).lastPathComponent)
            } else if let target = entry.target, !names.isEmpty {
                names[names.count - 1] = URL(fileURLWithPath: target).lastPathComponent
            }
        }
        return names
    }

}

nonisolated struct Cask: Decodable, Identifiable, Hashable {
    let token: String
    let fullToken: String?
    let tap: String?
    let name: [String]
    let desc: String?
    let homepage: String
    let url: String?
    let sha256: String?
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

    /// Executable names this cask links into the brew prefix (e.g. "claude").
    var binaryArtifactNames: [String] {
        artifacts?.flatMap(\.binaryNames) ?? []
    }

    /// Raw source paths of declared `binary` artifacts.
    var binarySourcePaths: [String] {
        artifacts?.flatMap(\.binarySourcePaths) ?? []
    }

    /// Package receipts removed by the cask's uninstall stanza.
    var packageIdentifiers: [String] {
        artifacts?.flatMap(\.packageIdentifiers) ?? []
    }

    /// Bundle IDs Homebrew asks to quit before uninstalling. Unlike pkgutil
    /// receipts, these identify the application itself and can safely relate
    /// App Store and direct-download variants of the same product family.
    var applicationBundleIdentifiers: [String] {
        artifacts?.flatMap(\.applicationBundleIdentifiers) ?? []
    }

    /// Application bundles installed indirectly by a package artifact.
    var deletedAppNames: [String] {
        artifacts?.flatMap(\.deletedAppNames) ?? []
    }

    var hasPackageArtifact: Bool {
        artifacts?.contains { $0.keys.contains("pkg") } == true
    }

    /// Conservative bundle-name candidates for package casks whose API metadata
    /// does not expose a normal `app` artifact.
    var packageAppNameCandidates: [String] {
        guard hasPackageArtifact else { return [] }
        var seen: Set<String> = []
        return (appArtifactNames + deletedAppNames + ["\(displayName).app"]).filter {
            seen.insert($0).inserted
        }
    }

    var isCLI: Bool {
        guard let artifacts, !artifacts.isEmpty else { return false }
        return artifacts.contains { !$0.keys.isDisjoint(with: ["binary", "stageOnly", "stage_only"]) }
            && !artifacts.contains { !$0.keys.isDisjoint(with: ["app", "suite", "pkg"]) }
    }

    var displayName: String {
        name.first ?? token
    }

    /// Newline separators keep a query from matching across field boundaries.
    var searchKey: String {
        "\(displayName)\n\(token)\n\(desc ?? "")".lowercased()
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
            url: String? = nil,
            sha256: String? = nil,
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
                url: url,
                sha256: sha256,
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
