//
//  LocalHomebrewError.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/08/2026.
//

import Foundation

enum LocalHomebrewError: LocalizedError {
    case brewBinaryNotFound
    case incompatibleBrewPath
    case appBundleNotFound(token: String)
    case brewCommandFailed(HomebrewCommandFailure)

    static func brewCommandFailed(
        args: [String],
        exitCode: Int32,
        stderr: String
    ) -> Self {
        .brewCommandFailed(HomebrewCommandFailure(
            arguments: args,
            exitCode: exitCode,
            diagnostic: stderr
        ))
    }

    /// Expected user or environment state is not an app defect.
    var shouldReport: Bool {
        switch self {
        case .brewBinaryNotFound, .incompatibleBrewPath:
            return false
        case .appBundleNotFound:
            return true
        case let .brewCommandFailed(failure):
            return failure.kind.shouldReport
        }
    }

    var commandFailure: HomebrewCommandFailure? {
        guard case let .brewCommandFailed(failure) = self else { return nil }
        return failure
    }

    /// "…because it is required by <token>, which is currently installed."
    static func dependentCask(stderr: String) -> String? {
        guard let range = stderr.range(
            of: #"required by ([A-Za-z0-9@._+-]+)"#,
            options: .regularExpression
        ) else { return nil }
        return String(stderr[range].dropFirst("required by ".count))
    }

    static func conflictingCask(stderr: String) -> String? {
        guard let range = stderr.range(
            of: #"conflicts with '[A-Za-z0-9@._+/-]+'"#,
            options: .regularExpression
        ) else { return nil }
        return String(
            stderr[range]
                .dropFirst("conflicts with '".count)
                .dropLast()
        )
    }

    static func caskConflictDescription(
        requestedCask: String,
        installedCask: String
    ) -> String {
        String(localized: .errorCaskConflict(
            requestedCask,
            installedCask,
            installedCask
        ))
    }

}

extension LocalHomebrewError {
    var errorDescription: String? {
        switch self {
        case .brewBinaryNotFound:
            return String(
                localized: "Couldn't locate the brew binary. Is Homebrew installed?"
            )
        case .incompatibleBrewPath:
            if HomebrewLocator.isAppleSilicon {
                return String(
                    localized: "This Mac requires Apple Silicon Homebrew. Choose /opt/homebrew/bin/brew in Settings."
                )
            }
            return String(
                localized: "This Mac requires Intel Homebrew. Choose /usr/local/bin/brew in Settings."
            )
        case let .appBundleNotFound(token):
            return String(localized: "Couldn't find an installed app for \(token).")
        case let .brewCommandFailed(failure):
            let args = failure.arguments
            let code = failure.exitCode
            let stderr = failure.diagnostic
            let cmd = (["brew"] + args).joined(separator: " ")
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if failure.kind == .permissionDenied {
                return String(localized: .errorAppManagementDenied)
            }
            if failure.kind == .strandedCaskroomApp {
                return String(localized: .errorStaleUpgradeRecord)
            }
            if failure.kind == .adoptVersionMismatch {
                return String(localized: .errorAdoptVersionMismatch)
            }
            switch failure.kind {
            case .binaryConflict:
                return "A leftover command-line tool from a previous installation "
                    + "is in the way. Replacing with Homebrew's version overwrites it — "
                    + "your settings and data are kept."
            case .appConflict:
                return "This app is already on your Mac, but Homebrew doesn't manage "
                    + "it yet. Adopt keeps your current copy and hands management to "
                    + "Homebrew; Replace installs Homebrew's copy fresh. Settings and "
                    + "data are kept either way."
            case .caskConflict:
                let requestedCask = args.drop(while: { $0 != "--cask" }).dropFirst().first
                guard let requestedCask,
                      let installedCask = Self.conflictingCask(stderr: trimmed)
                else { return String(localized: .errorCaskConflictUnknown) }
                return Self.caskConflictDescription(
                    requestedCask: requestedCask,
                    installedCask: installedCask
                )
            case .caskDependency:
                let dependent = Self.dependentCask(stderr: trimmed)
                return "This can't be uninstalled because "
                    + (dependent.map { "“\($0)” needs it" } ?? "another installed app needs it")
                    + ". Uninstall \(dependent.map { "“\($0)”" } ?? "that app") first, "
                    + "then try again."
            case .missingUninstallScript where args.first == "upgrade":
                return "The app's uninstall helper is missing, which blocks the "
                    + "update. Repair & Reinstall clears it and installs the new "
                    + "version fresh — your settings and data are kept."
            case .missingUninstallScript:
                return "The app's uninstall helper is missing, so Homebrew can't run "
                    + "its normal cleanup. Force Uninstall removes the app anyway."
            case .sudoDeclined:
                return "This step needs your administrator password. "
                    + "Try again and enter your password when CaskHub asks for it."
            case .sudoWrongPassword:
                return "The password wasn't accepted. "
                    + "Try again and re-enter your administrator password."
            case .sudoNotAdmin:
                return "This step needs an administrator account. "
                    + "Your macOS user doesn't have administrator rights, so Homebrew "
                    + "can't complete it."
            case .sudoPolicyDenied:
                return String(
                    localized: """
                    Your administrator has restricted the command Homebrew needs to run. \
                    Contact your administrator or install this app using your organization's approved method.
                    """
                )
            case .processKilled:
                return "The operation was interrupted before it finished. Try again."
            case .packageNewerInstalled:
                return "The vendor installer refused because a newer version is already "
                    + "installed. Downgrade & Adopt can download Homebrew's version first, "
                    + "remove the current package with the cask's uninstall steps, and then "
                    + "install the older version."
            case .packageAlreadyInstalled:
                return "The vendor installer refused to reinstall the version already on this "
                    + "Mac. Replace with Homebrew Version can download it first, remove the "
                    + "current package with the cask's uninstall steps, and install it fresh."
            case .packageUpgradeFailed:
                return "The vendor package installer could not upgrade the existing app in "
                    + "place. Replace with Homebrew Version can stage the download, remove the "
                    + "current package with the cask's uninstall steps, and install it fresh."
            case .brewBusy:
                return "Another Homebrew process is using the same download or installation "
                    + "files. Wait for it to finish, then try again."
            case .brewLockCleanupRace, .downloadCacheRace:
                return String(
                    localized: "Homebrew's temporary download state changed while the operation was finishing. Try again."
                )
            case .brewArchitectureMismatch:
                return String(
                    localized: """
                    Homebrew tried to run code for the wrong processor architecture. \
                    Select the compatible Homebrew path in Settings, then try again.
                    """
                )
            case .homebrewRuntimeIncompatible:
                return String(
                    localized: """
                    This Homebrew installation cannot read the current cask definition. \
                    Update Homebrew, then try again. If it still fails, run `brew doctor` in Terminal.
                    """
                )
            case .portableRubyUnavailable:
                return String(
                    localized: """
                    Homebrew could not prepare its Portable Ruby runtime. \
                    Check access to GitHub and GHCR, then update Homebrew and try again.
                    """
                )
            case .dmgMountCancelled:
                return String(
                    localized: "macOS canceled opening the disk image. Try again and approve the disk image if macOS asks for confirmation."
                )
            case .dmgMountBusy:
                return String(
                    localized: "The disk image is already in use. Eject any mounted copy of it, then try again."
                )
            case .dmgReadOnly:
                return String(
                    localized: """
                    Homebrew could not extract this disk image because its layout is read-only. \
                    Try again once; if it repeats, the cask needs to be corrected upstream.
                    """
                )
            case .requireSHAPolicy:
                return String(
                    localized: """
                    Your Homebrew settings require a checksum, but this cask uses an unversioned download without one. \
                    Remove `--require-sha` from `HOMEBREW_CASK_OPTS` to install it.
                    """
                )
            case .artifactConflict:
                return String(
                    localized: """
                    Homebrew found an existing item at the destination. \
                    Remove or move that item manually, then try again.

                    \(trimmed)
                    """
                )
            case .networkFailure:
                return String(
                    localized: """
                    Homebrew could not reach a required download host. \
                    Check your network, VPN, proxy, and DNS settings, then try again.
                    """
                )
            case .storageFull:
                return String(
                    localized: "There is not enough free storage to complete this operation. Free some space, then try again."
                )
            case .filesystemPermissionDenied:
                return String(
                    localized: """
                    Homebrew could not write to one of its temporary or installation folders. \
                    Run `brew doctor`, correct the permissions it reports, then try again.
                    """
                )
            case .quarantineInvalid:
                return String(
                    localized: """
                    The download is missing valid macOS quarantine metadata. \
                    Remove the cached download and let Homebrew download it again; \
                    do not bypass the security check.
                    """
                )
            case .homebrewNotWritable:
                return "Homebrew cannot write to one or more directories in its prefix. Run "
                    + "`brew doctor`, repair the ownership it reports, then try again."
            case .brewAPIUnavailable:
                return "Homebrew could not obtain a valid package from its API. Wait a few "
                    + "minutes and try again; if it persists, update Homebrew."
            case .platformUnsupported:
                return String(
                    localized: "This app is not available for this Mac's processor architecture or macOS version."
                )
            case .checksumMismatch:
                return String(localized: .errorChecksumMismatch)
            default:
                break
            }
            return trimmed.isEmpty
                ? String(localized: "`\(cmd)` failed (exit \(code)).")
                : String(localized: "`\(cmd)` failed (exit \(code)): \(trimmed)")
        }
    }

}
