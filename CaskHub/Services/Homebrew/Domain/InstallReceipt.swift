//
//  InstallReceipt.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/04/2026.
//

import Foundation

nonisolated struct InstallReceipt {
    let appBundleNames: [String]
    let lastUpdatedAt: Date?

    init(jsonData: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        lastUpdatedAt = (root["time"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue)
        }

        var apps: [String] = []
        if let artifacts = root["uninstall_artifacts"] as? [[String: Any]] {
            for artifact in artifacts {
                if let entries = artifact["artifact"] as? [Any], entries.count == 2,
                   let source = entries[0] as? String,
                   let options = entries[1] as? [String: Any],
                   let target = options["target"] as? String,
                   let name = ArtifactStanza.applicationArtifactName(source: source, target: target) {
                    apps.append(name)
                }
                guard let appList = artifact["app"] as? [Any] else { continue }
                for entry in appList {
                    if let name = entry as? String {
                        apps.append(name)
                    } else if let dict = entry as? [String: Any],
                              let target = dict["target"] as? String,
                              !apps.isEmpty {
                        // `app "X.app", target: "Y.app"` — the on-disk bundle is the target.
                        apps[apps.count - 1] = URL(fileURLWithPath: target).lastPathComponent
                    }
                }
            }
        }
        appBundleNames = apps
    }
}
