//
//  MaintenanceParsingTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 19/08/2026.
//

@testable import CaskHub
import XCTest

final class MaintenanceParsingTests: XCTestCase {

    // MARK: - brew doctor

    func test_doctor_ready_output_yields_no_warnings() {
        let output = "Your system is ready to brew.\n"
        XCTAssertTrue(BrewDoctorParser.warnings(from: output).isEmpty)
    }

    func test_doctor_warnings_are_split_into_checks() {
        let output = """
        Please note that these warnings are just used to help the Homebrew maintainers
        with debugging if you file an issue.

        Warning: Broken symlinks were found. Remove them with `brew cleanup`:
          /opt/homebrew/lib/libfoo.dylib
          /opt/homebrew/lib/libbar.dylib

        Warning: Unbrewed dylibs were found in /usr/local/lib.
        If you didn't put them there on purpose you should delete them:
          /usr/local/lib/libweird.dylib
        """
        let checks = BrewDoctorParser.warnings(from: output)

        XCTAssertEqual(checks.count, 2)
        XCTAssertEqual(checks[0].label, "Broken symlinks were found")
        XCTAssertEqual(checks[0].status, .advisory)
        XCTAssertEqual(checks[0].detail, """
        Remove them with `brew cleanup`:
        /opt/homebrew/lib/libfoo.dylib
        /opt/homebrew/lib/libbar.dylib
        """)
        XCTAssertEqual(checks[1].label, "Unbrewed dylibs were found in /usr/local/lib")
        XCTAssertEqual(checks[1].detail, """
        If you didn't put them there on purpose you should delete them:
        /usr/local/lib/libweird.dylib
        """)
    }

    func test_doctor_long_warning_keeps_the_full_log() {
        let paths = (1...20).map { "  /usr/local/lib/lib\($0).dylib" }
        let output = (["Warning: Unbrewed dylibs were found in /usr/local/lib."] + paths)
            .joined(separator: "\n")
        let checks = BrewDoctorParser.warnings(from: output)

        XCTAssertEqual(checks.count, 1)
        let lines = checks[0].detail.split(separator: "\n")
        XCTAssertEqual(lines.count, 20)
        XCTAssertEqual(lines.last, "/usr/local/lib/lib20.dylib")
    }

    // MARK: - brew cleanup --dry-run

    func test_cleanup_sums_superseded_kegs_and_ignores_cache_lines() {
        let output = """
        Would remove: /opt/homebrew/Cellar/openssl@3/3.1.0 (6,090 files, 28.2MB)
        Would remove: /Users/ali/Library/Caches/Homebrew/firefox--119.0.dmg (120.5MB)
        Would remove: /opt/homebrew/Caskroom/figma/124.7 (3 files, 200MB)
        ==> This operation would free approximately 348.7MB of disk space.
        """
        XCTAssertEqual(
            BrewCleanupParser.supersededKegBytes(from: output),
            29_569_843 + 209_715_200
        )
    }

    func test_cleanup_size_parsing_handles_units() {
        XCTAssertEqual(BrewCleanupParser.lastSizeBytes(in: "x (816B)"), 816)
        XCTAssertEqual(BrewCleanupParser.lastSizeBytes(in: "x (123 files, 4.5KB)"), 4608)
        XCTAssertEqual(BrewCleanupParser.lastSizeBytes(in: "x (1.2GB)"), 1_288_490_188)
        XCTAssertNil(BrewCleanupParser.lastSizeBytes(in: "no size here"))
    }

    func test_cleanup_estimate_is_zero_for_clean_system() {
        XCTAssertEqual(BrewCleanupParser.supersededKegBytes(from: ""), 0)
    }

    // MARK: - Version comparison

    func test_version_normalization_strips_prefix_and_git_suffix() {
        XCTAssertEqual(MaintenanceVersion.normalized("6.0.18-29-ga2005e5"), "6.0.18")
        XCTAssertEqual(MaintenanceVersion.normalized("v0.7.1"), "0.7.1")
        XCTAssertEqual(MaintenanceVersion.normalized("4.6.15"), "4.6.15")
    }

    func test_version_comparison_covers_current_ahead_and_behind() {
        XCTAssertEqual(MaintenanceVersion.isCurrent(local: "4.6.15", latest: "4.6.15"), true)
        XCTAssertEqual(MaintenanceVersion.isCurrent(local: "6.0.18-29-ga2005e5", latest: "6.0.18"), true)
        XCTAssertEqual(MaintenanceVersion.isCurrent(local: "6.1", latest: "6.0.18"), true)
        XCTAssertEqual(MaintenanceVersion.isCurrent(local: "4.6.15", latest: "4.7.0"), false)
        XCTAssertEqual(MaintenanceVersion.isCurrent(local: "4.6", latest: "4.6.1"), false)
        XCTAssertNil(MaintenanceVersion.isCurrent(local: "?", latest: "4.7.0"))
    }

    // MARK: - brew autoremove --dry-run

    func test_autoremove_parses_formula_names() {
        let output = """
        ==> Would autoremove 3 unneeded formulae:
        libyaml
        pcre2
        python-setuptools
        """
        XCTAssertEqual(
            BrewAutoremoveParser.formulae(from: output),
            ["libyaml", "pcre2", "python-setuptools"]
        )
    }

    func test_autoremove_empty_output_yields_no_names() {
        XCTAssertTrue(BrewAutoremoveParser.formulae(from: "").isEmpty)
    }
}
