//
//  HomebrewFailureReporting.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/11/2026.
//

import Foundation

/// Who produced a failure; the first part of its Sentry issue title.
nonisolated enum FailureArea: String, Sendable {
    case homebrew = "Homebrew"
    case device = "Device"
    case network = "Network"
    case vendor = "Vendor"
    case caskHub = "CaskHub"
}

nonisolated extension HomebrewFailureKind {
    var area: FailureArea {
        switch self {
        case .askpassUnavailable, .appBundleNotFound:
            .caskHub
        case .permissionDenied, .fullDiskAccessRequired, .filesystemPermissionDenied, .homebrewNotWritable,
             .storageFull, .sudoDeclined, .sudoWrongPassword, .sudoNotAdmin, .sudoPolicyDenied,
             .xcodeLicenseNotAccepted, .dmgMountBusy, .dmgMountCancelled, .dmgMountFailed,
             .brewArchitectureMismatch, .platformUnsupported, .incompatibleBrewPath, .brewBinaryNotFound,
             .requireSHAPolicy, .quarantineInvalid:
            .device
        case .networkFailure, .downloadFailed, .downloadBroken, .checksumMismatch, .brewAPIUnavailable:
            .network
        case .packageInstallerFailed, .packageUpgradeFailed, .packageNewerInstalled, .packageAlreadyInstalled:
            .vendor
        default:
            .homebrew
        }
    }

    /// `app-conflict` becomes `Homebrew.AppConflict`.
    var issueType: String {
        area.rawValue + "." + rawValue.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    /// Only the user's machine and network count as expected; anything CaskHub might cause stays an error.
    var reportsAsWarning: Bool {
        area == .device || area == .network
    }
}

nonisolated extension HomebrewCommandFailure {
    /// One issue per class and brew command; unknown failures also split by their cleaned Error line.
    var stableFingerprint: [String]? {
        guard let subcommand else { return nil }
        return [kind.issueType, subcommand] + (kind == .unknown ? [normalizedHeadline] : [])
    }

    /// The Error line with the cask, paths, URLs and numbers replaced, so it reads the same for every cask.
    var normalizedHeadline: String {
        guard let line = diagnosticReport?.headline else { return "" }
        let unnamed = redactedName.map { line.replacingOccurrences(of: $0, with: "<cask>", options: .caseInsensitive) } ?? line
        let token = redactedName.map(CaskReference.bareToken)
        return String(HomebrewDiagnosticRedactor.normalized(unnamed, token: token).prefix(160))
    }

    var diagnosticReport: (headline: String, text: String)? {
        HomebrewDiagnosticRedactor.report(diagnostic)
    }

    var rateLimitSignature: String {
        (stableFingerprint ?? [kind.issueType, "missing-subcommand"]).joined(separator: ":")
    }

    private var redactedName: String? {
        arguments.first == "untap" ? arguments.last : arguments.drop(while: { $0 != "--cask" }).dropFirst().first
    }
}
