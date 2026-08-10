//
//  AppManagementPermissionTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 10/08/2026.
//

@testable import CaskHub
import XCTest

final class AppManagementPermissionTests: XCTestCase {
    private let targets = [
        URL(fileURLWithPath: "/Applications/A.app"),
        URL(fileURLWithPath: "/Applications/B.app"),
        URL(fileURLWithPath: "/Applications/C.app"),
        URL(fileURLWithPath: "/Applications/D.app"),
        URL(fileURLWithPath: "/Applications/E.app")
    ]

    func test_probe_reports_denied_on_first_blocked_write_and_stops() {
        var attempted: [URL] = []
        let status = AppManagementPermission.probe(targets: targets) { url in
            attempted.append(url)
            return url.lastPathComponent == "B.app" ? .blocked : .allowed
        }
        XCTAssertEqual(status, .denied)
        XCTAssertEqual(attempted, Array(targets.prefix(2)))
    }

    func test_probe_reports_denied_when_block_follows_allowed_writes() {
        let status = AppManagementPermission.probe(targets: targets) { url in
            url.lastPathComponent == "C.app" ? .blocked : .allowed
        }
        XCTAssertEqual(status, .denied)
    }

    func test_probe_reports_granted_after_three_allowed_writes_and_stops() {
        var attempted: [URL] = []
        let status = AppManagementPermission.probe(targets: targets) { url in
            attempted.append(url)
            return .allowed
        }
        XCTAssertEqual(status, .granted)
        XCTAssertEqual(attempted.count, 3)
    }

    func test_probe_reports_granted_when_single_candidate_allows() {
        let status = AppManagementPermission.probe(targets: [targets[0]]) { _ in .allowed }
        XCTAssertEqual(status, .granted)
    }

    func test_probe_skips_unwritable_candidates_without_verdict() {
        let status = AppManagementPermission.probe(targets: targets) { url in
            url.lastPathComponent == "D.app" ? .allowed : .skipped
        }
        XCTAssertEqual(status, .granted)
    }

    func test_probe_reports_unknown_when_no_candidate_accepts_a_write() {
        XCTAssertEqual(
            AppManagementPermission.probe(targets: targets) { _ in .skipped },
            .unknown
        )
        XCTAssertEqual(AppManagementPermission.probe(targets: []) { _ in .allowed }, .unknown)
    }
}
