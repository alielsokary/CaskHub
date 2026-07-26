//
//  AppManagementPermission.swift
//  CaskHub
//
//  Created by Ali Elsokary on 19/07/2026.
//

import AppKit
import Foundation

/// macOS "App Management" privacy permission (System Settings → Privacy & Security
/// → App Management). There is no query API — status is probed by asking the kernel,
/// via `access(2)`, whether CaskHub may write inside app bundles it doesn't own.
enum AppManagementPermission {
    enum Status: Equatable {
        case granted, denied, unknown
    }

    @MainActor
    static func openSystemSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!
        )
    }

    /// Non-invasive probe: `access(2)` consults the App Management gate, so a bundle
    /// whose Contents is POSIX-writable (per its ownership bits) yet fails W_OK can
    /// only mean TCC is denying us. Nothing is written. One such bundle proves
    /// denied; "granted" needs every candidate writable, because same-team and
    /// never-Gatekeeper-registered bundles pass regardless of the permission.
    /// (Never pre-filter targets with isWritableFile — it calls access(2) too, and
    /// silently drops exactly the bundles that would report the denial.)
    nonisolated static func probe() -> Status {
        var sawWritable = false
        for bundle in probeTargets() {
            let contents = bundle.appendingPathComponent("Contents").path
            guard posixWritable(contents) else { continue }
            if access(contents, W_OK) != 0 {
                return .denied
            }
            sawWritable = true
        }
        return sawWritable ? .granted : .unknown
    }

    /// Bundles macOS actually protects: provenance-tracked (untracked bundles aren't
    /// gated; Apple's own apps carry no provenance, which also rules out SIP-protected
    /// ones like Safari). Our own bundle is exempt from TCC entirely.
    private nonisolated static func probeTargets() -> [URL] {
        let apps = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let ownBundle = Bundle.main.bundleURL.lastPathComponent
        return apps.filter {
            $0.pathExtension == "app"
                && $0.lastPathComponent != ownBundle
                && getxattr($0.path, "com.apple.provenance", nil, 0, 0, 0) > 0
        }
    }

    /// Writability from the file mode alone — deliberately blind to TCC.
    private nonisolated static func posixWritable(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        if info.st_uid == getuid() {
            return info.st_mode & mode_t(S_IWUSR) != 0
        }
        return info.st_mode & mode_t(S_IWOTH) != 0
    }
}
