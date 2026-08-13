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
        XCTAssertEqual(fieldSamples.count, 14)

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

    func test_unknown_fingerprint_is_bounded_without_private_context() throws {
        let first = unknownFailure(
            token: "cask-alpha",
            diagnostic: """
            Error: cask-alpha failed for /Users/alice at /private/tmp/homebrew-one/payload.dmg
            Source https://one.example/cask-alpha/1.2.3/payload.dmg version 1.2.3 build 42
            Hash aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            UUID 123e4567-e89b-12d3-a456-426614174000
            """
        )
        let second = unknownFailure(
            token: "cask-beta",
            diagnostic: """
            Error: cask-beta failed for /Users/bob at /private/tmp/homebrew-two/payload.dmg
            Source https://two.example/cask-beta/9.8.7/payload.dmg version 9.8.7 build 99
            Hash bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
            UUID 987e6543-e21b-43d3-b654-426614179999
            """
        )

        XCTAssertEqual(first.kind, .unknown)
        XCTAssertEqual(second.kind, .unknown)
        let firstFingerprint = try XCTUnwrap(first.stableFingerprint)
        let secondFingerprint = try XCTUnwrap(second.stableFingerprint)
        XCTAssertEqual(firstFingerprint, secondFingerprint)
        XCTAssertEqual(
            firstFingerprint,
            ["brewCommandFailed", "install", "unknown"]
        )
        XCTAssertFalse(first.rateLimitSignature.contains("alice"))
        XCTAssertFalse(first.rateLimitSignature.contains("cask-alpha"))

        let different = unknownFailure(
            token: "cask-gamma",
            diagnostic: "Error: renderer crashed before launch"
        )
        XCTAssertEqual(firstFingerprint, different.stableFingerprint)
    }

    func test_unknown_disk_image_output_keeps_a_reportable_mount_class() {
        let failure = HomebrewCommandFailure(
            arguments: ["install", "--cask", "example"],
            exitCode: 1,
            diagnostic: "Error: `/usr/bin/hdiutil attach example.dmg` exited with 1: erreur inconnue"
        )

        XCTAssertEqual(failure.kind, .dmgMountFailed)
        XCTAssertTrue(failure.kind.shouldReport)
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
        XCTAssertFalse(error.shouldReport)
        XCTAssertEqual(
            CaskOperationFailureFactory.make(
                from: error,
                strandedCopyExists: false
            ).recoveries,
            [.updateHomebrew]
        )
    }

    func test_terminal_environment_failure_wins_over_download_wrapper() {
        let failure = HomebrewCommandFailure(
            arguments: ["install", "--cask", "example"],
            exitCode: 1,
            diagnostic: "Error: example: Download failed on Cask 'example' with message: "
                + "No space left on device"
        )

        XCTAssertEqual(failure.kind, .storageFull)
        XCTAssertFalse(failure.kind.shouldReport)
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
