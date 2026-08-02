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

    func test_oversized_output_keeps_important_lines_and_tail() {
        let filler = String(repeating: "x", count: 9_000)
        let output = "Error: something broke\n" + filler
        let result = HomebrewOutputDiagnostics.make(from: output)
        XCTAssertTrue(result.hasPrefix("Error: something broke"))
        XCTAssertLessThanOrEqual(result.count, 8_192)
    }
}
