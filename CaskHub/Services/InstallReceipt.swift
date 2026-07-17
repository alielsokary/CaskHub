//
//  InstallReceipt.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/04/2026.
//

import Foundation

nonisolated struct InstallReceipt {
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
