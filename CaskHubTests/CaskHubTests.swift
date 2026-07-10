//
//  CaskHubTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 08/02/2026.
//

@testable import CaskHub
import XCTest

final class CaskHubTests: XCTestCase {
    private func makeCask(version: String) -> Cask {
        Cask(
            token: "test",
            fullToken: nil,
            tap: nil,
            name: ["Test"],
            desc: nil,
            homepage: "https://example.com",
            url: nil,
            version: version,
            installed: nil,
            bundleVersion: nil,
            bundleShortVersion: nil,
            outdated: false,
            deprecated: false,
            disabled: false,
            autoUpdates: nil
        )
    }

    func testDisplayVersionStripsPackagingSuffixes() {
        XCTAssertEqual(makeCask(version: "125.0").displayVersion, "125.0")
        XCTAssertEqual(makeCask(version: "125.0,build42").displayVersion, "125.0")
        XCTAssertEqual(makeCask(version: "125.0_1").displayVersion, "125.0")
        XCTAssertEqual(makeCask(version: "1.2.3-beta").displayVersion, "1.2.3")
        XCTAssertEqual(makeCask(version: "2024.10.13").displayVersion, "2024.10.13")
        // Entirely non-numeric versions fall back to the raw value.
        XCTAssertEqual(makeCask(version: "beta").displayVersion, "beta")
    }

    func testMetaLineOmitsUnknownDownloads() {
        XCTAssertEqual(makeCask(version: "125.0").metaLine(downloads: "1.2M"), "↓ 1.2M · v125.0")
        XCTAssertEqual(makeCask(version: "125.0").metaLine(downloads: nil), "v125.0")
    }
}
