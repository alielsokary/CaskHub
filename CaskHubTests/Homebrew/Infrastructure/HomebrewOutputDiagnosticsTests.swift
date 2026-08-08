//
//  HomebrewOutputDiagnosticsTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 02/08/2026.
//

@testable import CaskHub
import XCTest

final class HomebrewOutputDiagnosticsTests: XCTestCase {
    func test_spinner_progress_frames_are_stripped() {
        let output = """
        Extracting  205.4MB/205.4MB⠴ Cask parallels (26.4.0-57513)
        Extracting  205.4MB/205.4MB⠲ Cask parallels (26.4.0-57513)
        Error: It seems there is already an App at '/Applications/Parallels Desktop.app'.
        """
        let result = HomebrewOutputDiagnostics.make(from: output)
        XCTAssertEqual(
            result,
            "Error: It seems there is already an App at '/Applications/Parallels Desktop.app'."
        )
    }

    func test_progress_metric_frames_without_spinner_are_stripped() {
        let output = """
        Cask webstorm (2026.2.0.1) ######     Downloading 653.3MB/  1.1GB
        Verified     41.7MB/ 41.7MB
        Error: Download failed
        """
        let result = HomebrewOutputDiagnostics.make(from: output)
        XCTAssertEqual(result, "Error: Download failed")
    }

    func test_download_url_lines_are_kept() {
        let output = """
        ==> Downloading https://formulae.brew.sh/api/cask.jws.json
        Error: curl: (28) Operation timed out
        """
        let result = HomebrewOutputDiagnostics.make(from: output)
        XCTAssertTrue(result.contains("==> Downloading https://formulae.brew.sh/api/cask.jws.json"))
        XCTAssertTrue(result.contains("Error: curl: (28) Operation timed out"))
    }

    func test_cleaned_output_classifies_buried_network_failure() {
        let frames = (0..<50).map { _ in
            "Cask webstorm (2026.2.0.1) ######     Downloading 653.3MB/  1.1GB⠚"
        }
        let output = (frames + ["curl: (28) Operation timed out after 30000 milliseconds"])
            .joined(separator: "\n")
        let cleaned = HomebrewOutputDiagnostics.make(from: output)
        XCTAssertEqual(LocalHomebrewError.failureClass(stderr: cleaned), "network-failure")
    }

    func test_short_output_passes_through_unchanged() {
        let output = "Error: Cask 'thorium' is not installed."
        XCTAssertEqual(HomebrewOutputDiagnostics.make(from: output), output)
    }

    func test_oversized_output_keeps_the_tail() {
        let output = String(repeating: "x", count: 9_000) + "\nError: something broke"
        let result = HomebrewOutputDiagnostics.make(from: output)
        XCTAssertTrue(result.hasSuffix("Error: something broke"))
        XCTAssertLessThanOrEqual(result.count, 4_000)
    }

    func test_tap_trust_advisory_is_stripped_keeping_the_error() {
        let output = """
        Warning: The following taps are not trusted:
          lihaoyun6/tap
        Homebrew is currently ignoring formulae, casks and commands from these taps \
        because tap trust is required.
        To trust these taps, run:
          brew trust lihaoyun6/tap
        Untap them with:
          brew untap lihaoyun6/tap
        To disable trust checks:
        export HOMEBREW_NO_REQUIRE_TAP_TRUST=1
        This is not recommended and will be removed in a later release.
        For more information, see:
          https://docs.brew.sh/Tap-Trust
        Error: quickrecorder: Download failed on Cask 'quickrecorder'
        """
        let result = HomebrewOutputDiagnostics.make(from: output)
        XCTAssertTrue(result.contains("Error: quickrecorder"))
        XCTAssertFalse(result.contains("brew trust"))
        XCTAssertFalse(result.contains("taps are not trusted"))
        XCTAssertFalse(result.contains("HOMEBREW_NO_REQUIRE_TAP_TRUST"))
    }

    func test_force_overwrite_warnings_are_stripped() {
        let output = """
        Warning: It seems there is already an App at '/Applications/MacDown.app'; overwriting.
        Error: Failure while executing; `/usr/bin/sudo -A -E -- /bin/rm -f -- x` exited with 1.
        """
        let result = HomebrewOutputDiagnostics.make(from: output)
        XCTAssertFalse(result.contains("already an App at"))
        XCTAssertNotEqual(LocalHomebrewError.failureClass(stderr: result), "app-conflict")
    }

    func test_long_payload_slices_near_the_last_error_line_keeping_context() {
        let preamble = (0..<60).map { "==> Installing dependency step \($0)" }
            .joined(separator: "\n")
        let output = preamble + "\nError: the decisive line\nfollow-up detail"
        let result = HomebrewOutputDiagnostics.make(from: output)
        XCTAssertTrue(result.contains("Error: the decisive line"))
        XCTAssertTrue(result.hasSuffix("follow-up detail"))
        XCTAssertFalse(result.contains("step 0"), "distant preamble is dropped")
        XCTAssertLessThan(result.count, 700, "decisive line stays within Sentry's head cap")
    }

    func test_slice_keeps_subprocess_root_cause_above_the_wrapper_error() {
        let preamble = (0..<50).map { "==> Running installer step \($0)" }
            .joined(separator: "\n")
        let output = preamble + "\nSorry, try again.\nSorry, try again.\n"
            + "sudo: 3 incorrect password attempts\n"
            + "Error: Failure while executing; `/usr/bin/sudo -A -E -- "
            + "/usr/sbin/installer -pkg /private/tmp/x.pkg -target /` exited with 1."
        let result = HomebrewOutputDiagnostics.make(from: output)
        XCTAssertTrue(result.contains("sudo: 3 incorrect password attempts"))
        XCTAssertEqual(
            LocalHomebrewError.failureClass(stderr: result),
            "sudo-wrong-password",
            "slicing must not strip the lines classification depends on"
        )
    }

    func test_tap_trust_lines_are_stripped_even_without_their_trigger_line() {
        let orphanedAdvisory = """
        Homebrew is currently ignoring formulae, casks and commands from these \
        taps because tap trust is required.
        To trust these taps, run:
          brew trust lihaoyun6/tap
          https://docs.brew.sh/Tap-Trust
        Error: something real broke
        """
        let result = HomebrewOutputDiagnostics.make(from: orphanedAdvisory)
        XCTAssertEqual(result, "Error: something real broke")
    }

    func test_short_payload_keeps_context_above_the_error_line() {
        let output = "==> Installing Cask foo\nError: the decisive line"
        XCTAssertEqual(HomebrewOutputDiagnostics.make(from: output), output)
    }

    func test_error_line_survives_a_trailing_progress_flood() {
        let frames = (0 ..< 100).map { _ in
            "Extracting  205.4MB/205.4MB⠴ Cask parallels (26.4.0-57513)"
        }
        let output = (["Error: installation failed for parallels"] + frames)
            .joined(separator: "\n")
        let result = HomebrewOutputDiagnostics.make(from: output)
        XCTAssertEqual(result, "Error: installation failed for parallels")
    }
}
