//
//  AppManagementPermission.swift
//  CaskHub
//
//  Created by Ali Elsokary on 19/07/2026.
//

import AppKit
import Foundation

/// macOS "App Management" privacy permission. No query API, and `access(2)` never
/// consults the gate (TCC enforces actual writes only), so status is probed
/// Homebrew-style: attempt a harmless write inside protected bundles.
nonisolated enum AppManagementPermission {
    enum Status: Equatable, Sendable {
        case granted, denied, unknown
    }

    enum Evidence: String, Equatable, Sendable {
        case target
        case generic
        case unverified
    }

    struct Assessment: Equatable, Sendable {
        let status: Status
        let evidence: Evidence?
    }

    enum WriteAttempt {
        case allowed, blocked, skipped
    }

    @MainActor
    static func openSystemSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!
        )
    }

    nonisolated static func probe() -> Status {
        assess(target: nil).status
    }

    /// Prefer the app that will actually be adopted. Root-owned bundles cannot
    /// be tested without another password prompt, so they fall back to the
    /// conservative multi-bundle probe and retain that weaker provenance.
    nonisolated static func assess(target: URL?) -> Assessment {
        assess(
            target: target,
            fallbackTargets: probeTargets(),
            attempt: attemptWrite
        )
    }

    nonisolated static func assess(
        target: URL?,
        fallbackTargets: [URL],
        attempt: (URL) -> WriteAttempt
    ) -> Assessment {
        if let target {
            switch attempt(target) {
            case .allowed:
                return Assessment(status: .granted, evidence: .target)
            case .blocked:
                return Assessment(status: .denied, evidence: .target)
            case .skipped:
                break
            }
        }

        let status = probe(targets: fallbackTargets, attempt: attempt)
        return Assessment(
            status: status,
            evidence: status == .unknown ? nil : .generic
        )
    }

    /// One blocked write proves denied; allowed writes are weaker evidence (bundles
    /// CaskHub installed itself are exempt), so granted needs three acceptances.
    nonisolated static func probe(
        targets: [URL],
        attempt: (URL) -> WriteAttempt
    ) -> Status {
        var allowed = 0
        for bundle in targets {
            switch attempt(bundle) {
            case .blocked:
                return .denied
            case .allowed:
                allowed += 1
                if allowed == 3 { return .granted }
            case .skipped:
                continue
            }
        }
        return .unknown
    }

    /// After the posixWritable guard only the TCC gate returns EPERM; EACCES (ACLs) is not it.
    private nonisolated static func attemptWrite(in bundle: URL) -> WriteAttempt {
        let contents = bundle.appendingPathComponent("Contents").path
        guard posixWritable(contents) else { return .skipped }
        let probePath = contents + "/.com.caskhub.permission-probe." + UUID().uuidString
        let fd = open(probePath, O_CREAT | O_WRONLY | O_EXCL, 0o644)
        guard fd >= 0 else {
            return errno == EPERM ? .blocked : .skipped
        }
        close(fd)
        unlink(probePath)
        return .allowed
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
