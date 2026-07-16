//
//  InstallReceipt.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/04/2026.
//

import Foundation

/// Minimal parser for Homebrew's per-cask install receipt at
/// `<Caskroom>/<token>/.metadata/INSTALL_RECEIPT.json`.
///
/// Uses `JSONSerialization` rather than `Decodable`: `uninstall_artifacts`
/// is a heterogeneous array of single-key dictionaries with mixed value
/// types. Decodable handles that shape too (`ArtifactStanza` decodes the
/// same kind of stanza with a custom key type), but extracting a single
/// key is fewer lines as a tree walk than as a custom `init(from:)`.
///
/// Marked `nonisolated` because the project uses `-default-isolation=MainActor`
/// and this parser is invoked from a background `Task.detached` in the scan loop.
nonisolated struct InstallReceipt {
    /// `.app` bundle filenames extracted from `uninstall_artifacts`, e.g. `["Firefox.app"]`.
    /// Empty when the cask installs no apps (CLI-only casks like `android-platform-tools`).
    ///
    /// Note: the receipt also contains `source.version` and `time`, but these freeze at the
    /// original install and never update after `brew upgrade`. The authoritative version comes
    /// from the Caskroom **version directory name**, and the date from its filesystem timestamp.
    let appBundleNames: [String]

    init(jsonData: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var apps: [String] = []
        if let artifacts = root["uninstall_artifacts"] as? [[String: Any]] {
            for artifact in artifacts {
                if let appList = artifact["app"] as? [String] {
                    apps.append(contentsOf: appList)
                }
            }
        }
        appBundleNames = apps
    }
}
