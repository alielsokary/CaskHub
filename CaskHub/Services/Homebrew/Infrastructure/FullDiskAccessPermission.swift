//
//  FullDiskAccessPermission.swift
//  CaskHub
//
//  Created by Ali Elsokary on 13/10/2026.
//

import AppKit
import Foundation

/// macOS "Full Disk Access" privacy permission. No query API, so status is probed
/// by opening locations only that permission unlocks.
nonisolated enum FullDiskAccessPermission {
    typealias Status = AppManagementPermission.Status

    @MainActor
    static func openSystemSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        )
    }

    static func probe() -> Status {
        probe(paths: probePaths, errorOpening: errorOpening)
    }

    /// Only EPERM is the TCC gate; a missing or mode-restricted path proves nothing.
    static func probe(paths: [String], errorOpening: (String) -> Int32?) -> Status {
        for path in paths {
            switch errorOpening(path) {
            case nil: return .granted
            case EPERM: return .denied
            default: continue
            }
        }
        return .unknown
    }

    /// The folder Homebrew's zap stanzas glob most often, then the system TCC database.
    private static var probePaths: [String] {
        [
            NSHomeDirectory() + "/Library/Application Support/com.apple.sharedfilelist"
                + "/com.apple.LSSharedFileList.ApplicationRecentDocuments",
            "/Library/Application Support/com.apple.TCC/TCC.db"
        ]
    }

    private static func errorOpening(_ path: String) -> Int32? {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return errno }
        close(descriptor)
        return nil
    }
}
