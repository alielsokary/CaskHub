//
//  HomebrewCommandFailure.swift
//  CaskHub
//
//  Created by Ali Elsokary on 12/08/2026.
//

import Foundation

nonisolated enum HomebrewFailureKind: String, Equatable, Sendable {
    case adoptVersionMismatch = "adopt-version-mismatch"
    case appConflict = "app-conflict"
    case artifactConflict = "artifact-conflict"
    case binaryConflict = "binary-conflict"
    case brewAPIUnavailable = "brew-api-unavailable"
    case brewArchitectureMismatch = "brew-architecture-mismatch"
    case brewBusy = "brew-busy"
    case brewLockCleanupRace = "brew-lock-cleanup-race"
    case caskConflict = "cask-conflict"
    case caskDependency = "cask-dependency"
    case checksumMismatch = "checksum-mismatch"
    case dmgMountBusy = "dmg-mount-busy"
    case dmgMountCancelled = "dmg-mount-cancelled"
    case dmgMountFailed = "dmg-mount-failed"
    case dmgReadOnly = "dmg-read-only"
    case downloadBroken = "download-broken"
    case downloadCacheRace = "download-cache-race"
    case downloadFailed = "download-failed"
    case exitNonzeroAfterSuccess = "exit-nonzero-after-success"
    case filesystemPermissionDenied = "filesystem-permission-denied"
    case homebrewNotWritable = "homebrew-not-writable"
    case homebrewRuntimeIncompatible = "homebrew-runtime-incompatible"
    case missingArtifactSource = "missing-artifact-source"
    case missingUninstallScript = "missing-uninstall-script"
    case networkFailure = "network-failure"
    case noDiagnosticOutput = "no-diagnostic-output"
    case notInstalled = "not-installed"
    case packageAlreadyInstalled = "pkg-already-installed"
    case packageInstallerFailed = "pkg-installer-failed"
    case packageNewerInstalled = "pkg-newer-installed"
    case packageUpgradeFailed = "pkg-upgrade-failed"
    case permissionDenied = "permission-denied"
    case platformUnsupported = "platform-unsupported"
    case portableRubyUnavailable = "portable-ruby-unavailable"
    case processKilled = "process-killed"
    case quarantineInvalid = "quarantine-invalid"
    case requireSHAPolicy = "require-sha-policy"
    case strandedCaskroomApp = "stranded-caskroom-app"
    case storageFull = "storage-full"
    case sudoDeclined = "sudo-declined"
    case sudoNotAdmin = "sudo-not-admin"
    case sudoPolicyDenied = "sudo-policy-denied"
    case sudoWrongPassword = "sudo-wrong-password"
    case unknown
    case unknownCask = "unknown-cask"
    case upgradeRefused = "upgrade-refused"

    var shouldReport: Bool {
        switch self {
        case .adoptVersionMismatch,
             .appConflict,
             .artifactConflict,
             .binaryConflict,
             .brewArchitectureMismatch,
             .brewBusy,
             .brewLockCleanupRace,
             .caskConflict,
             .checksumMismatch,
             .dmgMountBusy,
             .dmgMountCancelled,
             .dmgReadOnly,
             .downloadCacheRace,
             .filesystemPermissionDenied,
             .homebrewRuntimeIncompatible,
             .networkFailure,
             .permissionDenied,
             .platformUnsupported,
             .portableRubyUnavailable,
             .quarantineInvalid,
             .requireSHAPolicy,
             .strandedCaskroomApp,
             .storageFull,
             .sudoDeclined,
             .sudoPolicyDenied,
             .sudoWrongPassword:
            false
        default:
            true
        }
    }
}

nonisolated struct HomebrewCommandFailure: Equatable, Sendable {
    let arguments: [String]
    let exitCode: Int32
    let diagnostic: String
    let kind: HomebrewFailureKind

    init(arguments: [String], exitCode: Int32, diagnostic: String) {
        self.arguments = arguments
        self.exitCode = exitCode
        self.diagnostic = diagnostic
        kind = Self.classify(
            arguments: arguments,
            exitCode: exitCode,
            diagnostic: diagnostic
        )
    }

    var subcommand: String? {
        arguments.first
    }

    var stableFingerprint: [String]? {
        guard let subcommand else { return nil }
        return ["brewCommandFailed", subcommand, kind.rawValue]
    }

    var rateLimitSignature: String {
        ["brewCommandFailed", subcommand ?? "missing-subcommand", kind.rawValue]
            .joined(separator: ":")
    }
}

nonisolated extension HomebrewCommandFailure {
    static func classify(
        arguments: [String],
        exitCode: Int32?,
        diagnostic: String
    ) -> HomebrewFailureKind {
        let text = diagnostic.lowercased()
        return privilegeKind(text: text, diagnostic: diagnostic)
            ?? processKind(text: text, exitCode: exitCode)
            ?? installerKind(text: text)
            ?? diskImageKind(text: text)
            ?? policyKind(text: text)
            ?? artifactKind(arguments: arguments, text: text, diagnostic: diagnostic)
            ?? environmentKind(text: text)
            ?? downloadKind(text: text)
            ?? (text.isBlank ? .noDiagnosticOutput : .unknown)
    }

    private struct Match {
        let fragments: [String]
        let kind: HomebrewFailureKind
    }

    private static func firstMatch(
        in text: String,
        _ matches: [Match]
    ) -> HomebrewFailureKind? {
        matches.first { match in
            match.fragments.allSatisfy(text.contains)
        }?.kind
    }

    private static func privilegeKind(
        text: String,
        diagnostic: String
    ) -> HomebrewFailureKind? {
        if isAppManagementDenial(diagnostic) { return .permissionDenied }
        return firstMatch(in: text, [
            Match(
                fragments: ["sorry, you are not allowed to preserve the environment"],
                kind: .sudoPolicyDenied
            ),
            Match(fragments: ["is not allowed to execute"], kind: .sudoPolicyDenied),
            Match(fragments: ["incorrect password attempt"], kind: .sudoWrongPassword),
            Match(fragments: ["sudo: no password was provided"], kind: .sudoDeclined),
            Match(fragments: ["sudo: a password is required"], kind: .sudoDeclined),
            Match(fragments: ["is not in the sudoers file"], kind: .sudoNotAdmin)
        ])
    }

    private static func processKind(
        text: String,
        exitCode: Int32?
    ) -> HomebrewFailureKind? {
        if let exitCode, [9, 15, 130].contains(exitCode), text.isBlank {
            return .processKilled
        }
        if text.contains("bad cpu type in executable"),
           text.contains("portable-ruby") || text.contains("homebrew/brew.sh") {
            return .brewArchitectureMismatch
        }
        return firstMatch(in: text, [
            Match(fragments: ["failed to download ruby"], kind: .portableRubyUnavailable),
            Match(
                fragments: ["failed to upgrade homebrew portable ruby"],
                kind: .portableRubyUnavailable
            )
        ])
    }

    private static func installerKind(text: String) -> HomebrewFailureKind? {
        firstMatch(in: text, [
            Match(
                fragments: ["a newer version of", "is already installed"],
                kind: .packageNewerInstalled
            ),
            Match(
                fragments: ["installer:", "is already installed"],
                kind: .packageAlreadyInstalled
            ),
            Match(
                fragments: ["installer:", "the upgrade failed"],
                kind: .packageUpgradeFailed
            ),
            Match(fragments: ["installer: the install failed"], kind: .packageInstallerFailed),
            Match(fragments: ["/usr/sbin/installer -pkg"], kind: .packageInstallerFailed),
            Match(
                fragments: ["uninstall script", "does not exist"],
                kind: .missingUninstallScript
            )
        ])
    }

    private static func diskImageKind(text: String) -> HomebrewFailureKind? {
        if text.contains("read-only file system"), text.contains("homebrew-dmg") {
            return .dmgReadOnly
        }
        if text.contains("hdiutil: attach canceled") { return .dmgMountCancelled }
        if text.contains("hdiutil"), text.contains("attach") {
            if text.contains("resource busy") || text.contains("ressource ist belegt") {
                return .dmgMountBusy
            }
            return .dmgMountFailed
        }
        return nil
    }

    private static func policyKind(text: String) -> HomebrewFailureKind? {
        if isHomebrewRuntimeIncompatible(text) { return .homebrewRuntimeIncompatible }
        return firstMatch(in: text, [
            Match(
                fragments: ["does not have a sha256 checksum defined", "--require-sha"],
                kind: .requireSHAPolicy
            ),
            Match(fragments: ["reports different checksum"], kind: .checksumMismatch),
            Match(fragments: ["sha256 mismatch"], kind: .checksumMismatch),
            Match(fragments: ["was not quarantined properly"], kind: .quarantineInvalid)
        ])
    }

    private static func artifactKind(
        arguments: [String],
        text: String,
        diagnostic: String
    ) -> HomebrewFailureKind? {
        if isStrandedApp(diagnostic) { return .strandedCaskroomApp }
        if text.contains("different from the one being installed")
            || (arguments.contains("--adopt") && text.contains("already an app at")) {
            return .adoptVersionMismatch
        }
        return firstMatch(in: text, [
            Match(fragments: ["is not there"], kind: .missingArtifactSource),
            Match(fragments: ["no cask with this name exists"], kind: .unknownCask),
            Match(fragments: ["no casks found"], kind: .unknownCask),
            Match(fragments: ["is not installed"], kind: .notInstalled),
            Match(fragments: ["already a binary at"], kind: .binaryConflict),
            Match(fragments: ["already an app at"], kind: .appConflict),
            Match(fragments: ["conflicts with"], kind: .caskConflict),
            Match(fragments: ["refusing to uninstall"], kind: .caskDependency),
            Match(
                fragments: ["it seems there is already a ", " at '"],
                kind: .artifactConflict
            )
        ])
    }

    private static func downloadKind(text: String) -> HomebrewFailureKind? {
        if isNetworkFailure(text) { return .networkFailure }
        return firstMatch(in: text, [
            Match(fragments: ["the requested url returned error:"], kind: .downloadBroken),
            Match(fragments: ["cannot download non-corrupt"], kind: .brewAPIUnavailable),
            Match(fragments: ["download failed on cask"], kind: .downloadFailed)
        ])
    }

    private static func environmentKind(text: String) -> HomebrewFailureKind? {
        firstMatch(in: text, [
            Match(fragments: ["process has already locked"], kind: .brewBusy),
            Match(fragments: ["gave up after waiting"], kind: .brewBusy),
            Match(fragments: ["please wait for it to finish"], kind: .brewBusy),
            Match(fragments: ["is already running"], kind: .brewBusy),
            Match(
                fragments: ["no such file or directory", ".lock", "dir_s_rmdir"],
                kind: .brewLockCleanupRace
            ),
            Match(
                fragments: [
                    "no such file or directory",
                    ".incomplete",
                    "library/caches/homebrew/downloads"
                ],
                kind: .downloadCacheRace
            ),
            Match(fragments: ["no space left on device"], kind: .storageFull),
            Match(
                fragments: ["permission denied", "/private/tmp/homebrew"],
                kind: .filesystemPermissionDenied
            ),
            Match(
                fragments: ["permission denied", "/opt/homebrew"],
                kind: .filesystemPermissionDenied
            ),
            Match(
                fragments: ["permission denied", "/usr/local/homebrew"],
                kind: .filesystemPermissionDenied
            ),
            Match(fragments: ["not writable by your user"], kind: .homebrewNotWritable),
            Match(
                fragments: ["this cask does not run on macos versions"],
                kind: .platformUnsupported
            ),
            Match(fragments: ["depends on hardware architecture"], kind: .platformUnsupported),
            Match(
                fragments: ["current os x version is not supported"],
                kind: .platformUnsupported
            ),
            Match(
                fragments: ["current macos version is not supported"],
                kind: .platformUnsupported
            ),
            Match(fragments: ["requires linux"], kind: .platformUnsupported),
            Match(fragments: ["error: not upgrading"], kind: .upgradeRefused),
            Match(fragments: ["successfully upgraded!"], kind: .exitNonzeroAfterSuccess)
        ])
    }

    private static func isAppManagementDenial(_ diagnostic: String) -> Bool {
        if diagnostic.localizedCaseInsensitiveContains(
            "does not have App Management permissions"
        ) {
            return true
        }
        return diagnostic.components(separatedBy: .newlines).contains { line in
            line.localizedCaseInsensitiveContains("Operation not permitted")
                && line.contains("/Applications/")
                && line.localizedCaseInsensitiveContains(".app")
        }
    }

    private static func isStrandedApp(_ diagnostic: String) -> Bool {
        diagnostic.localizedCaseInsensitiveContains("already an App at")
            && diagnostic.localizedCaseInsensitiveContains("Caskroom")
    }

    private static func isHomebrewRuntimeIncompatible(_ text: String) -> Bool {
        if text.contains("cask_loader.rb"), text.contains("undefined method") {
            return true
        }
        guard text.contains("definition is invalid") else { return false }
        return text.contains("undefined method")
            || text.contains("command_wrapper")
            || text.contains("postflight_steps")
            || text.contains("unknown key:")
    }

    private static func isNetworkFailure(_ text: String) -> Bool {
        let curlCodes = [5, 6, 7, 18, 28, 35, 56, 92]
        return curlCodes.contains { text.contains("curl: (\($0))") }
            || text.contains("nameresolutionerror")
            || text.contains("could not resolve host")
            || text.contains("failed to resolve")
    }

}

private nonisolated extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
