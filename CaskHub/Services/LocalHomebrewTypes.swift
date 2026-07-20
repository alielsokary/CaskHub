//
//  LocalHomebrewTypes.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Foundation

struct LocalCaskInstallation: Hashable, Identifiable {
    let token: String
    let installedVersion: String
    let installedAt: Date?
    let appBundleNames: [String]

    /// Brew still lists this cask, but its app was removed outside Homebrew
    /// (or its install receipt is gone) — opens and upgrades are doomed.
    let isZombie: Bool

    nonisolated init(
        token: String,
        installedVersion: String,
        installedAt: Date?,
        appBundleNames: [String],
        isZombie: Bool = false
    ) {
        self.token = token
        self.installedVersion = installedVersion
        self.installedAt = installedAt
        self.appBundleNames = appBundleNames
        self.isZombie = isZombie
    }

    var id: String {
        token
    }
}

enum CaskAction: Equatable {
    case opening
    case installing
    case adopting
    case updating
    case uninstalling
    case queued

    var inProgressLabel: String {
        switch self {
        case .opening: return "Opening…"
        case .installing: return "Installing…"
        case .adopting: return "Adopting…"
        case .updating: return "Updating…"
        case .uninstalling: return "Uninstalling…"
        case .queued: return "Queued…"
        }
    }
}

enum LocalHomebrewError: LocalizedError {
    case brewBinaryNotFound
    case appBundleNotFound(token: String)
    case brewCommandFailed(args: [String], exitCode: Int32, stderr: String)

    /// Machine states (no Homebrew installed), not bugs — never worth a Sentry event.
    var isEnvironmental: Bool {
        if case .brewBinaryNotFound = self { return true }
        return false
    }

    /// Coarse classes for Sentry grouping — one issue per way brew fails, not per cask.
    static func failureClass(stderr: String) -> String {
        if isStrandedApp(stderr: stderr) { return "stranded-caskroom-app" }
        return failurePatterns.first { stderr.contains($0.fragment) }?.classification
            ?? "uncategorized"
    }

    private static let failurePatterns: [(fragment: String, classification: String)] = [
        ("is not there", "missing-artifact-source"),
        ("different from the one being installed", "adopt-version-mismatch"),
        ("Operation not permitted", "permission-denied"),
        ("No Cask with this name exists", "unknown-cask"),
        ("No casks found", "unknown-cask"),
        ("is not installed", "not-installed"),
        ("reports different checksum", "checksum-mismatch"),
        ("SHA256 mismatch", "checksum-mismatch"),
        ("already an App at", "app-conflict")
    ]

    /// A previous interrupted operation parked the real .app inside the Caskroom
    /// version directory; every upgrade then fails until the copy is cleared.
    static func isStrandedApp(stderr: String) -> Bool {
        stderr.contains("already an App at") && stderr.contains("Caskroom")
    }

    var errorDescription: String? {
        switch self {
        case .brewBinaryNotFound:
            return "Couldn't locate the brew binary. Is Homebrew installed?"
        case let .appBundleNotFound(token):
            return "Couldn't find an installed app for \(token)."
        case let .brewCommandFailed(args, code, stderr):
            let cmd = (["brew"] + args).joined(separator: " ")
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isAppManagementDenial(stderr: trimmed) {
                return "macOS blocked CaskHub from modifying apps on your Mac. "
                    + "Enable CaskHub under System Settings → Privacy & Security → "
                    + "App Management, then try again."
            }
            if Self.isStrandedApp(stderr: trimmed) {
                return "A previous update left an old copy of the app inside Homebrew's "
                    + "records, and Homebrew refuses every upgrade until it's cleared. "
                    + "Repair removes the leftover copy and reinstalls the app fresh — "
                    + "your settings and data are kept."
            }
            if Self.isAdoptMismatch(args: args, stderr: trimmed) {
                return "Your installed copy doesn't match the version Homebrew has on record, "
                    + "so it can't be adopted as-is. You can replace it with Homebrew's copy "
                    + "instead — your settings and data are kept."
            }
            if trimmed.contains("reports different checksum") || trimmed.contains("SHA256 mismatch") {
                return "The download doesn't match the checksum Homebrew has on record — "
                    + "the developer likely replaced the release file after it was published. "
                    + "This isn't a problem with your Mac; Homebrew refuses mismatched downloads "
                    + "for security. Try again in a day or two once the cask is updated."
            }
            return trimmed.isEmpty
                ? "`\(cmd)` failed (exit \(code))."
                : "`\(cmd)` failed (exit \(code)): \(trimmed)"
        }
    }

    /// The App Management (TCC) permission gating modification of other apps' bundles.
    static func isAppManagementDenial(stderr: String) -> Bool {
        stderr.contains("Operation not permitted")
    }

    /// `brew install --adopt` refuses when the on-disk app differs from the cask's version.
    static func isAdoptMismatch(args: [String], stderr: String) -> Bool {
        args.contains("--adopt")
            && (stderr.contains("different from the one being installed")
                || stderr.contains("already an App at"))
    }
}
