//
//  LocalHomebrewError.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/08/2026.
//

import Foundation

enum LocalHomebrewError: LocalizedError {
    case brewBinaryNotFound
    case appBundleNotFound(token: String)
    case brewCommandFailed(args: [String], exitCode: Int32, stderr: String)

    /// Failures with a complete in-app recovery path are user state, not defects.
    var shouldReport: Bool {
        switch self {
        case .brewBinaryNotFound:
            return false
        case .appBundleNotFound:
            return true
        case let .brewCommandFailed(_, code, stderr):
            return !Self.recoverableFailureClasses.contains(
                Self.failureClass(stderr: stderr, exitCode: code)
            )
        }
    }

    /// Coarse classes for Sentry grouping — one issue per way brew fails, not per cask.
    static func failureClass(stderr: String, exitCode: Int32? = nil) -> String {
        if isStrandedApp(stderr: stderr) { return "stranded-caskroom-app" }
        if isAppManagementDenial(stderr: stderr) { return "permission-denied" }
        if stderr.contains("uninstall script"), stderr.contains("does not exist") {
            return "missing-uninstall-script"
        }
        if let exitCode, [9, 15, 130].contains(exitCode),  // SIGKILL/SIGTERM/SIGINT
           stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "process-killed"
        }
        return failurePatterns.first { stderr.contains($0.fragment) }?.classification
            ?? "uncategorized"
    }

    private static let failurePatterns: [(fragment: String, classification: String)] = [
        // First: a failed prompt outranks incidental fragments below it.
        ("sudo: no password was provided", "sudo-declined"),
        ("sudo: a password is required", "sudo-declined"),
        ("incorrect password attempt", "sudo-wrong-password"),
        ("is not in the sudoers file", "sudo-not-admin"),
        ("is not there", "missing-artifact-source"),
        ("different from the one being installed", "adopt-version-mismatch"),
        ("No Cask with this name exists", "unknown-cask"),
        ("No casks found", "unknown-cask"),
        ("is not installed", "not-installed"),
        // Checksum above the download family: brew wraps some in download phrasing.
        ("reports different checksum", "checksum-mismatch"),
        ("SHA256 mismatch", "checksum-mismatch"),
        // Installer/dmg above the download family: vendor pkg scripts run curl too.
        ("attach failed - Resource busy", "dmg-mount-busy"),
        ("installer: The install failed", "pkg-installer-failed"),
        ("installer: The upgrade failed", "pkg-installer-failed"),
        ("/usr/sbin/installer -pkg", "pkg-installer-failed"),
        // HTTP errors (curl 22) split out: persistent 404s flag dead casks.
        ("The requested URL returned error:", "download-broken"),
        ("curl: (5)", "network-failure"),
        ("curl: (6)", "network-failure"),
        ("curl: (7)", "network-failure"),
        ("curl: (18)", "network-failure"),
        ("curl: (28)", "network-failure"),
        ("curl: (35)", "network-failure"),
        ("curl: (56)", "network-failure"),
        ("curl: (92)", "network-failure"),
        ("Cannot download non-corrupt", "brew-api-unavailable"),
        ("Download failed on Cask", "download-failed"),
        ("already a Binary at", "binary-conflict"),
        ("already an App at", "app-conflict"),
        ("conflicts with", "cask-conflict"),
        ("Refusing to uninstall", "cask-dependency"),
        ("This cask does not run on macOS versions", "platform-unsupported"),
        ("depends on hardware architecture", "platform-unsupported"),
        ("requires Linux", "platform-unsupported"),
        ("is already running", "brew-busy"),
        ("Please wait for it to finish", "brew-busy"),
        ("not writable by your user", "homebrew-not-writable"),
        ("Error: Not upgrading", "upgrade-refused"),
        // Last: success text must never outrank a real error line above.
        ("successfully upgraded!", "exit-nonzero-after-success")
    ]

    /// A class moves here only once the app offers a complete recovery path.
    private static let recoverableFailureClasses: Set<String> = [
        "adopt-version-mismatch",
        "app-conflict",
        "binary-conflict",
        "checksum-mismatch",
        "network-failure",
        "permission-denied",
        "stranded-caskroom-app",
        "sudo-declined",
        "sudo-wrong-password"
    ]

    /// "…because it is required by <token>, which is currently installed."
    static func dependentCask(stderr: String) -> String? {
        guard let range = stderr.range(
            of: #"required by ([A-Za-z0-9@._+-]+)"#,
            options: .regularExpression
        ) else { return nil }
        return String(stderr[range].dropFirst("required by ".count))
    }

    /// A previous interrupted operation parked the real .app inside the Caskroom
    /// version directory; every upgrade then fails until the copy is cleared.
    static func isStrandedApp(stderr: String) -> Bool {
        stderr.contains("already an App at") && stderr.contains("Caskroom")
    }

    var errorDescription: String? {
        switch self {
        case .brewBinaryNotFound:
            return String(
                localized: "Couldn't locate the brew binary. Is Homebrew installed?"
            )
        case let .appBundleNotFound(token):
            return String(localized: "Couldn't find an installed app for \(token).")
        case let .brewCommandFailed(args, code, stderr):
            let cmd = (["brew"] + args).joined(separator: " ")
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isAppManagementDenial(stderr: trimmed) {
                return String(localized: .errorAppManagementDenied)
            }
            if Self.isStrandedApp(stderr: trimmed) {
                return String(localized: .errorStaleUpgradeRecord)
            }
            if Self.isAdoptMismatch(args: args, stderr: trimmed) {
                return String(localized: .errorAdoptVersionMismatch)
            }
            switch Self.failureClass(stderr: trimmed, exitCode: code) {
            case "binary-conflict":
                return "A leftover command-line tool from a previous installation "
                    + "is in the way. Replacing with Homebrew's version overwrites it — "
                    + "your settings and data are kept."
            case "app-conflict":
                return "This app is already on your Mac, but Homebrew doesn't manage "
                    + "it yet. Adopt keeps your current copy and hands management to "
                    + "Homebrew; Replace installs Homebrew's copy fresh. Settings and "
                    + "data are kept either way."
            case "cask-dependency":
                let dependent = Self.dependentCask(stderr: trimmed)
                return "This can't be uninstalled because "
                    + (dependent.map { "“\($0)” needs it" } ?? "another installed app needs it")
                    + ". Uninstall \(dependent.map { "“\($0)”" } ?? "that app") first, "
                    + "then try again."
            case "missing-uninstall-script" where args.first == "upgrade":
                return "The app's uninstall helper is missing, which blocks the "
                    + "update. Repair & Reinstall clears it and installs the new "
                    + "version fresh — your settings and data are kept."
            case "missing-uninstall-script":
                return "The app's uninstall helper is missing, so Homebrew can't run "
                    + "its normal cleanup. Force Uninstall removes the app anyway."
            case "sudo-declined":
                return "This step needs your administrator password. "
                    + "Try again and enter your password when CaskHub asks for it."
            case "sudo-wrong-password":
                return "The password wasn't accepted. "
                    + "Try again and re-enter your administrator password."
            case "sudo-not-admin":
                return "This step needs an administrator account. "
                    + "Your macOS user doesn't have administrator rights, so Homebrew "
                    + "can't complete it."
            case "process-killed":
                return "The operation was interrupted before it finished. Try again."
            default:
                break
            }
            if trimmed.contains("reports different checksum") || trimmed.contains("SHA256 mismatch") {
                return String(localized: .errorChecksumMismatch)
            }
            return trimmed.isEmpty
                ? String(localized: "`\(cmd)` failed (exit \(code)).")
                : String(localized: "`\(cmd)` failed (exit \(code)): \(trimmed)")
        }
    }

    /// The App Management (TCC) permission gating modification of other apps' bundles.
    static func isAppManagementDenial(stderr: String) -> Bool {
        if stderr.contains("does not have App Management permissions") { return true }
        return stderr.components(separatedBy: .newlines).contains { line in
            line.contains("Operation not permitted")
                && line.contains("/Applications/")
                && line.contains(".app")
        }
    }

    /// `brew install --adopt` refuses when the on-disk app differs from the cask's version.
    static func isAdoptMismatch(args: [String], stderr: String) -> Bool {
        args.contains("--adopt")
            && (stderr.contains("different from the one being installed")
                || stderr.contains("already an App at"))
    }
}
