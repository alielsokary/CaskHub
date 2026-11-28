//
//  HomebrewCommandFailureTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 12/08/2026.
//

@testable import CaskHub
import XCTest

final class HomebrewCommandFailureTests: XCTestCase {
    private struct Fixture {
        let name: String
        let arguments: [String]
        let diagnostic: String
        let expectedKind: HomebrewFailureKind
    }

    func test_field_samples_map_to_typed_failure_kinds() {
        XCTAssertEqual(fieldSamples.count, 15)

        for fixture in fieldSamples {
            let diagnostic = HomebrewOutputDiagnostics.make(from: fixture.diagnostic)
            let failure = HomebrewCommandFailure(
                arguments: fixture.arguments,
                exitCode: 1,
                diagnostic: diagnostic
            )

            XCTAssertEqual(failure.kind, fixture.expectedKind, fixture.name)
        }
    }

    func test_terminal_privilege_failure_wins_over_incidental_signals() {
        let diagnostic = """
        Error: Failed to download ruby from https://ghcr.io/example
        hdiutil: attach canceled
        Sorry, user demo is not allowed to execute '/bin/cp' as root on this Mac.
        """

        XCTAssertEqual(
            HomebrewCommandFailure.classify(
                arguments: ["install", "--cask", "example"],
                exitCode: 1,
                diagnostic: diagnostic
            ),
            .sudoPolicyDenied
        )
    }

    func test_unknown_failures_group_by_their_cleaned_error_line() throws {
        let first = unknownFailure(
            token: "cask-alpha",
            diagnostic: """
            ==> Fetching cask-alpha from homebrew/cask
            Error: cask-alpha failed for /Users/Alice Smith/Documents/Tax Return.pdf
            Source https://one.example/cask-alpha/1.2.3/payload.dmg version 1.2.3 build 42
            """
        )
        let second = unknownFailure(
            token: "cask-beta",
            diagnostic: "Error: cask-beta failed for /Users/Bob Jones/Documents/Tax Return.pdf"
        )
        let different = unknownFailure(
            token: "cask-gamma",
            diagnostic: "Error: renderer crashed before launch"
        )

        XCTAssertEqual(first.kind, .unknown)
        let fingerprint = try XCTUnwrap(first.stableFingerprint)
        XCTAssertEqual(fingerprint, ["Homebrew.Unknown", "install", "error: <cask> failed for <path>"])
        XCTAssertEqual(fingerprint, second.stableFingerprint)
        XCTAssertNotEqual(fingerprint, different.stableFingerprint)
        XCTAssertEqual(first.rateLimitSignature, second.rateLimitSignature)
        XCTAssertNotEqual(first.rateLimitSignature, different.rateLimitSignature)
        XCTAssertFalse(first.rateLimitSignature.contains("alice"))
        XCTAssertFalse(first.rateLimitSignature.contains("cask-alpha"))
    }

    func test_issue_title_line_never_carries_tokens_or_authorization_values() {
        let failure = unknownFailure(
            token: "example",
            diagnostic: "Error: GitHub rejected ghp_AbCdEfGhIjKlMnOpQrStUvWxYz012345 via Bearer s3cr3t-Value"
        )

        XCTAssertFalse(failure.normalizedHeadline.contains("ghp_"), failure.normalizedHeadline)
        XCTAssertFalse(failure.normalizedHeadline.contains("s3cr3t"), failure.normalizedHeadline)
        XCTAssertFalse(failure.rateLimitSignature.contains("s3cr3t"))
    }

    func test_known_failures_group_by_class_and_command_only() {
        let first = HomebrewCommandFailure(
            arguments: ["install", "--cask", "t3-code"], exitCode: 1,
            diagnostic: "Error: It seems there is already an App at '/Applications/T3 Code (Beta).app'."
        )
        let second = HomebrewCommandFailure(
            arguments: ["install", "--cask", "libreoffice"], exitCode: 1,
            diagnostic: "Error: It seems there is already an App at '/Applications/LibreOffice.app'."
        )
        XCTAssertEqual(first.stableFingerprint, ["Homebrew.AppConflict", "install"])
        XCTAssertEqual(first.stableFingerprint, second.stableFingerprint)
    }

    func test_machine_provenance_splits_app_invariants_from_user_state() {
        let architecture = """
        This cask depends on hardware architecture being one of \
        [{type: :arm, bits: 64}], but you are running {type: :intel, bits: 64}.
        """
        XCTAssertEqual(
            HomebrewCommandFailure.classify(
                arguments: ["install"],
                exitCode: 1,
                diagnostic: architecture,
                machineIsAppleSilicon: true
            ),
            .brewArchitectureMismatch
        )
        XCTAssertEqual(
            HomebrewCommandFailure.classify(
                arguments: ["install"],
                exitCode: 1,
                diagnostic: architecture,
                machineIsAppleSilicon: false
            ),
            .platformUnsupported
        )
    }

    func test_askpass_provenance_splits_user_decision_from_helper_failure() {
        let sudoOutput = "sudo: no password was provided"
        XCTAssertEqual(
            HomebrewCommandFailure(
                arguments: ["install"],
                exitCode: 1,
                diagnostic: sudoOutput,
                askpassUserCancelled: true
            ).kind,
            .sudoDeclined
        )
        XCTAssertEqual(
            HomebrewCommandFailure(
                arguments: ["install"],
                exitCode: 1,
                diagnostic: sudoOutput,
                askpassUserCancelled: false
            ).kind,
            .askpassUnavailable
        )
        XCTAssertEqual(
            HomebrewCommandFailure(
                arguments: ["install"],
                exitCode: 1,
                diagnostic: "",
                askpassUserCancelled: true
            ).kind,
            .sudoDeclined
        )
    }

    func test_disabled_cask_refusal_has_its_own_reportable_kind() {
        let failure = HomebrewCommandFailure(
            arguments: ["install", "--cask", "tomatobar"],
            exitCode: 1,
            diagnostic: "Error: tomatobar has been disabled because it does not pass the macOS Gatekeeper check! "
                + "It was disabled on 2026-09-01."
        )

        XCTAssertEqual(failure.kind, .caskDisabled)
        XCTAssertFalse(failure.kind.isNormallyExternal, "CaskHub should never have offered this install")
    }

    func test_only_proven_user_decision_is_explicit() {
        XCTAssertTrue(HomebrewFailureKind.sudoDeclined.isExplicitUserDecision)
        XCTAssertFalse(HomebrewFailureKind.sudoWrongPassword.isExplicitUserDecision)
        XCTAssertFalse(HomebrewFailureKind.dmgMountCancelled.isExplicitUserDecision)
    }

    func test_unknown_disk_image_output_keeps_a_reportable_mount_class() {
        let failure = HomebrewCommandFailure(
            arguments: ["install", "--cask", "example"],
            exitCode: 1,
            diagnostic: "Error: `/usr/bin/hdiutil attach example.dmg` exited with 1: erreur inconnue"
        )

        XCTAssertEqual(failure.kind, .dmgMountFailed)
        XCTAssertFalse(failure.kind.isNormallyExternal)
    }

    func test_runtime_incompatible_failure_offers_update_homebrew() {
        let error = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "gimp"],
            exitCode: 1,
            stderr: """
            Error: Cask 'gimp' definition is invalid: invalid 'command_wrapper' stanza: \
            Unknown key: :executable. Valid keys are: :target, :content
            """
        )

        XCTAssertEqual(error.commandFailure?.kind, .homebrewRuntimeIncompatible)
        XCTAssertFalse(error.commandFailure?.kind.isNormallyExternal ?? true, "an outdated Homebrew is reported to Sentry")
        XCTAssertEqual(
            CaskOperationFailureFactory.make(
                from: error,
                strandedCopyExists: false
            ).recoveries,
            [.updateHomebrew]
        )
    }

    func test_interrupted_uninstall_offers_force_uninstall_instead_of_reinstalling() {
        let error = LocalHomebrewError.brewCommandFailed(
            args: ["uninstall", "--cask", "obsidian"],
            exitCode: 1,
            stderr: "Error: It seems there is already an App at '/opt/homebrew/Caskroom/obsidian/1.14.4/Obsidian.app'."
        )

        let presentation = CaskOperationFailureFactory.make(from: error, strandedCopyExists: true)

        XCTAssertEqual(error.commandFailure?.kind, .strandedCaskroomApp)
        XCTAssertEqual(presentation.recoveries, [.forceUninstall])
        XCTAssertTrue(presentation.message.contains("Force Uninstall"))
        XCTAssertFalse(presentation.message.contains("upgrade"))
    }

    func test_zap_blocked_by_full_disk_access_is_classified_and_can_finish_without_data_removal() {
        let error = LocalHomebrewError.brewCommandFailed(
            args: ["uninstall", "--cask", "obsidian", "--zap"],
            exitCode: 1,
            stderr: """
            ==> Backing up App 'Obsidian.app' to '/opt/homebrew/Caskroom/obsidian/1.14.4/Obsidian.app'
            ==> Removing App '/Applications/Obsidian.app'
            ==> Dispatching zap stanza
            Error: Unable to remove some files. Please enable Full Disk Access for your terminal under \
            System Settings → Privacy & Security → Full Disk Access.
            """
        )

        let presentation = CaskOperationFailureFactory.make(from: error, strandedCopyExists: true)

        XCTAssertEqual(error.commandFailure?.kind.rawValue, "full-disk-access-required")
        XCTAssertEqual(error.commandFailure?.stableFingerprint?.count, 2)
        XCTAssertEqual(presentation.recoveries, [.forceUninstall, .openFullDiskAccessSettings])
        XCTAssertTrue(presentation.message.contains("CaskHub"))
        XCTAssertFalse(presentation.message.contains("your terminal"))
    }

    func test_xcode_license_failure_has_specific_guidance_without_reinstall_recovery() {
        let diagnostic = "Error: You have not agreed to the Xcode license. Please resolve this by running:\n"
            + "  sudo xcodebuild -license accept"
        for command in ["install", "upgrade", "uninstall"] {
            let error = LocalHomebrewError.brewCommandFailed(args: [command, "--cask", "example"],
                                                           exitCode: 1, stderr: diagnostic)
            XCTAssertEqual(error.commandFailure?.kind.rawValue, "xcode-license-not-accepted")
            XCTAssertEqual(error.commandFailure?.stableFingerprint?.count, 2)
            XCTAssertFalse(error.commandFailure?.kind.isNormallyExternal ?? true)
            let presentation = CaskOperationFailureFactory.make(from: error, strandedCopyExists: true)
            XCTAssertTrue(presentation.message.contains("review and accept"))
            XCTAssertTrue(presentation.message.contains("sudo xcodebuild -license"))
            XCTAssertFalse(presentation.message.contains("-license accept"))
            XCTAssertTrue(presentation.recoveries.isEmpty)
        }
        XCTAssertEqual(HomebrewCommandFailure.classify(
            arguments: ["upgrade"], exitCode: 1, diagnostic: "Error: Vendor license not found."
        ), .unknown)
    }

    func test_terminal_environment_failure_wins_over_download_wrapper() {
        let failure = HomebrewCommandFailure(
            arguments: ["install", "--cask", "example"],
            exitCode: 1,
            diagnostic: "Error: example: Download failed on Cask 'example' with message: "
                + "No space left on device"
        )

        XCTAssertEqual(failure.kind, .storageFull)
        XCTAssertFalse(failure.kind.isNormallyExternal, "a full disk is reported to Sentry")
        XCTAssertEqual(failure.kind.issueType, "Device.StorageFull")
        XCTAssertTrue(failure.kind.reportsAsWarning)
    }

    func test_out_of_disk_extract_and_download_failures_are_storage_full() {
        let extract = """
        \tfrom /opt/homebrew/Library/Homebrew/sandbox_operation.rb:31:in '<main>'

        Error: Not enough disk space to extract:
          /private/tmp/homebrew-dmg20261127-3426-32qebu/mount
        Free up space on the filesystems containing these directories:
          /private/tmp
        Then try again.
        Error: imazing: Download failed for imazing.
        """
        let download = """
        ==> Fetching downloads for: visual-studio-code
        Error: Could not write download to /Users/me/Library/Caches/Homebrew/downloads/x--VSCode-darwin-arm64.zip.incomplete
        Check that the destination has enough free disk space and is writable.
        curl: (23) Failure writing output to destination, passed 16384 returned 0
        Error: visual-studio-code: Download failed for visual-studio-code.
        """
        let unwritable = """
        Error: Could not write download to /Users/me/Library/Caches/Homebrew/downloads/x--VSCode-darwin-arm64.zip.incomplete
        Check that the destination has enough free disk space and is writable.
        curl: (23) client returned ERROR on write of 821 bytes
        """

        XCTAssertEqual(HomebrewCommandFailure.classify(arguments: ["upgrade"], exitCode: 1, diagnostic: extract), .storageFull)
        XCTAssertEqual(HomebrewCommandFailure.classify(arguments: ["install"], exitCode: 1, diagnostic: download), .storageFull)
        XCTAssertNotEqual(HomebrewCommandFailure.classify(arguments: ["install"], exitCode: 1, diagnostic: unwritable), .storageFull)
    }

    func test_install_success_requires_the_exact_requested_cask() {
        for flags in [[], ["--adopt"], ["--force"]] {
            for badge in ["", "🍺  ", "✅  "] {
                XCTAssertEqual(HomebrewCommandFailure.classify(
                    arguments: ["install", "--cask", "inkstitch"] + flags,
                    exitCode: 1, diagnostic: badge + "inkstitch was successfully installed!\nError: cleanup failed"
                ), .exitNonzeroAfterSuccess)
            }
        }
        for token in ["inkscape", "other-inkstitch"] {
            XCTAssertEqual(HomebrewCommandFailure.classify(
                arguments: ["install", "--cask", "inkstitch"], exitCode: 1,
                diagnostic: "🍺  \(token) was successfully installed!\nError: inkstitch failed"
            ), .unknown)
        }
        for arguments in [["install"], ["uninstall", "--cask", "inkstitch"]] {
            XCTAssertEqual(HomebrewCommandFailure.classify(
                arguments: arguments, exitCode: 1, diagnostic: "🍺  inkstitch was successfully installed!"
            ), .unknown)
        }
    }

    private func unknownFailure(
        token: String,
        diagnostic: String
    ) -> HomebrewCommandFailure {
        HomebrewCommandFailure(
            arguments: ["install", "--cask", token],
            exitCode: 1,
            diagnostic: diagnostic
        )
    }

    private var fieldSamples: [Fixture] {
        [
            Fixture(
                name: "affinity lock cleanup race",
                arguments: ["install", "--cask", "affinity"],
                diagnostic: "✘ Cask affinity (3.2.3,4646)\n"
                    + "Error: No such file or directory @ dir_s_rmdir - "
                    + "/opt/homebrew/var/homebrew/locks/"
                    + "5fec6af861f84cb794dbe427cd42eeb35b42018950e42a5e84ae4d9e1ec0edfe--"
                    + "Affinity Affinity Store 4646.zip.incomplete.download.lock",
                expectedKind: .brewLockCleanupRace
            ),
            Fixture(
                name: "skim canceled disk image mount",
                arguments: ["install", "--cask", "skim"],
                diagnostic: "Error: Failure while executing; `/usr/bin/env hdiutil attach "
                    + "-plist -nobrowse -readonly -mountrandom "
                    + "/private/tmp/homebrew-dmg20260811-1901-g5sxas "
                    + "/Users/justin/Library/Caches/Homebrew/downloads/skim.dmg` exited with 1.\n"
                    + "There may be a problem with this disk image. "
                    + "Are you sure you want to open it?\n"
                    + "hdiutil: attach canceled",
                expectedKind: .dmgMountCancelled
            ),
            Fixture(
                name: "alt-tab portable ruby download",
                arguments: ["install", "--cask", "alt-tab"],
                diagnostic: "Warning: Failed to set filetime 1784072529 on\n"
                    + "Warning: '/Users/aj/Library/Caches/Homebrew/portable-ruby-4.0.6."
                    + "arm64_big_sur.bottle.tar.gz.incomplete': No such file or directory\n"
                    + "Error: Failed to download ruby from the following locations:\n"
                    + "- https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:83a3ff85\n"
                    + "Error: Failed to upgrade Homebrew Portable Ruby!",
                expectedKind: .portableRubyUnavailable
            ),
            Fixture(
                name: "portable ruby upgrade held by a parallel brew",
                arguments: ["fetch", "--cask", "zoom"],
                diagnostic: "lockf: 200: already locked\n"
                    + "Error: Another `brew vendor-install ruby` process is already running.\n"
                    + "Please wait for it to finish or terminate it to continue.\n"
                    + "Error: Failed to upgrade Homebrew Portable Ruby!",
                expectedKind: .brewBusy
            ),
            Fixture(
                name: "daisydisk require-sha policy",
                arguments: ["install", "--cask", "daisydisk", "--adopt"],
                diagnostic: "✔︎ Cask daisydisk (4.34.2) Downloaded 5.4MB/5.4MB\n"
                    + "Error: Cask 'daisydisk' does not have a sha256 checksum defined.\n"
                    + "This means you have the --require-sha option set, perhaps in your "
                    + "`$HOMEBREW_CASK_OPTS`.",
                expectedKind: .requireSHAPolicy
            ),
            Fixture(
                name: "libreoffice download lock",
                arguments: ["install", "--cask", "libreoffice-language-pack"],
                diagnostic: "Warning: Waiting for another Homebrew process to finish downloading "
                    + "/Users/em/Library/Caches/Homebrew/downloads/libreoffice.dmg.incomplete...\n"
                    + "Error: A `brew install --cask libreoffice-language-pack` process has "
                    + "already locked /Users/em/Library/Caches/Homebrew/downloads/"
                    + "libreoffice.dmg.incomplete.\n"
                    + "Gave up after waiting 180 seconds. Terminate it to continue.",
                expectedKind: .brewBusy
            ),
            Fixture(
                name: "amazon music unsupported macOS",
                arguments: ["install", "--cask", "amazon-music"],
                diagnostic: "✔︎ Cask amazon-music (9.5.2) Downloaded 141.2MB/141.2MB\n"
                    + "==> Running installer script\n"
                    + "The current OS X version is not supported\n"
                    + "Error: installer script exited with 1: "
                    + "The current OS X version is not supported",
                expectedKind: .platformUnsupported
            ),
            Fixture(
                name: "google chrome sudo policy",
                arguments: ["install", "--cask", "google-chrome"],
                diagnostic: "Sorry, user u116558 is not allowed to execute "
                    + "'/bin/cp -pR /opt/homebrew/Caskroom/google-chrome/151.0.7922.109/"
                    + "Google Chrome.app /Applications/Google Chrome.app' as root on IX01877468.\n"
                    + "Error: `/usr/bin/sudo -A -E -- /bin/cp -pR` exited with 1.",
                expectedKind: .sudoPolicyDenied
            ),
            Fixture(
                name: "anythingllm completed download only",
                arguments: ["install", "--cask", "anythingllm", "--adopt"],
                diagnostic: "✔︎ Cask anythingllm (1.15.0) Downloaded 504.5MB/504.5MB",
                expectedKind: .noDiagnosticOutput
            ),
            Fixture(
                name: "deepl Intel Homebrew on Apple silicon",
                arguments: ["install", "--cask", "deepl", "--adopt"],
                diagnostic: "/usr/local/Homebrew/Library/Homebrew/brew.sh: line 688: "
                    + "/usr/local/Homebrew/Library/Homebrew/vendor/portable-ruby/current/bin/ruby: "
                    + "Bad CPU type in executable\n"
                    + "/usr/local/Homebrew/Library/Homebrew/brew.sh: line 688: "
                    + "Undefined error: 0",
                expectedKind: .brewArchitectureMismatch
            ),
            Fixture(
                name: "backdrop read-only disk image",
                arguments: ["install", "--cask", "backdrop"],
                diagnostic: "Error: Read-only file system @ apply2files - "
                    + "/private/tmp/homebrew-dmg20260812-23432-84kktm/"
                    + "dmg.S5Is7D/.DropDMGBackground/background.tiff",
                expectedKind: .dmgReadOnly
            ),
            Fixture(
                name: "docker sudo environment policy",
                arguments: ["install", "--cask", "docker-desktop", "--adopt"],
                diagnostic: "✔︎ Cask docker-desktop (4.86.0,236216) Downloaded 574.0MB/574.0MB\n"
                    + "==> Using sudo to gain ownership of path "
                    + "'/usr/local/bin/docker-credential-osxkeychain'\n"
                    + "Error: `/usr/bin/sudo -A -E -- /bin/rm -f` exited with 1.\n"
                    + "sudo: sorry, you are not allowed to preserve the environment",
                expectedKind: .sudoPolicyDenied
            ),
            Fixture(
                name: "musaicfm screen saver conflict",
                arguments: ["install", "--cask", "musaicfm"],
                diagnostic: "Error: It seems there is already a Screen Saver at "
                    + "'/Users/beluga/Library/Screen Savers/MusaicFM.saver'.",
                expectedKind: .artifactConflict
            ),
            Fixture(
                name: "macfuse sudo environment policy",
                arguments: ["install", "--cask", "macfuse"],
                diagnostic: "Sorry, try again.\n"
                    + "installer: Package name is macFUSE\n"
                    + "installer: The install was successful.\n"
                    + "Error: `/usr/bin/sudo -A -E -- rm "
                    + "/usr/local/include/.homebrew-write-test` exited with 1.\n"
                    + "sudo: sorry, you are not allowed to preserve the environment",
                expectedKind: .sudoPolicyDenied
            ),
            Fixture(
                name: "gimp incompatible cask definition",
                arguments: ["install", "--cask", "gimp"],
                diagnostic: "✔︎ JSON API packages.arm64_golden_gate.jws.json "
                    + "Downloaded 15.8MB/15.8MB\n"
                    + "Error: Cask 'gimp' definition is invalid: invalid 'command_wrapper' "
                    + "stanza: Unknown key: :executable. Valid keys are: :target, :content",
                expectedKind: .homebrewRuntimeIncompatible
            )
        ]
    }
}
