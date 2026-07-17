//
//  CaskHubTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 08/02/2026.
//

@testable import CaskHub
import XCTest

final class CaskHubTests: XCTestCase {
    @MainActor
    func test_display_version_strips_packaging_suffixes() {
        XCTAssertEqual(makeCask("test", version: "125.0").displayVersion, "125.0")
        XCTAssertEqual(makeCask("test", version: "125.0,build42").displayVersion, "125.0")
        XCTAssertEqual(makeCask("test", version: "125.0_1").displayVersion, "125.0")
        XCTAssertEqual(makeCask("test", version: "1.2.3-beta").displayVersion, "1.2.3")
        XCTAssertEqual(makeCask("test", version: "2024.10.13").displayVersion, "2024.10.13")
        // Entirely non-numeric versions fall back to the raw value.
        XCTAssertEqual(makeCask("test", version: "beta").displayVersion, "beta")
    }

    @MainActor
    func test_meta_line_omits_unknown_downloads() {
        XCTAssertEqual(makeCask("test", version: "125.0").metaLine(downloads: "1.2M"), "↓ 1.2M · v125.0")
        XCTAssertEqual(makeCask("test", version: "125.0").metaLine(downloads: nil), "v125.0")
    }

    /// An empty queue must still clear the flag — a stuck `isUpdatingAll`
    /// would disable the Update All button forever.
    @MainActor
    func test_update_all_with_empty_queue_clears_flag() async {
        let local = LocalHomebrewService()
        await local.updateAll(tokens: [])
        XCTAssertFalse(local.isUpdatingAll)
    }
}
