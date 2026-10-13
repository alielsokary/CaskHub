//
//  FullDiskAccessPermissionTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 13/10/2026.
//

@testable import CaskHub
import XCTest

final class FullDiskAccessPermissionTests: XCTestCase {
    func test_a_blocked_read_proves_denial() {
        let status = FullDiskAccessPermission.probe(paths: ["/missing", "/protected", "/readable"]) {
            ["/missing": ENOENT, "/protected": EPERM][$0]
        }

        XCTAssertEqual(status, .denied)
    }

    func test_a_successful_read_proves_the_grant() {
        let status = FullDiskAccessPermission.probe(paths: ["/missing", "/readable", "/protected"]) {
            ["/missing": ENOENT, "/protected": EPERM][$0]
        }

        XCTAssertEqual(status, .granted)
    }

    func test_missing_or_unreadable_paths_prove_nothing() {
        let status = FullDiskAccessPermission.probe(paths: ["/missing", "/locked"]) {
            ["/missing": ENOENT, "/locked": EACCES][$0]
        }

        XCTAssertEqual(status, .unknown)
    }
}
