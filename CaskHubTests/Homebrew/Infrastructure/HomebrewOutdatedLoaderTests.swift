//
//  HomebrewOutdatedLoaderTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 05/10/2026.
//

@testable import CaskHub
import XCTest

final class HomebrewOutdatedLoaderTests: XCTestCase {
    func test_report_uses_homebrews_outdated_flag_and_rejects_unparseable_output() throws {
        // Trimmed `brew info --installed --cask --json=v2`; `third` comes from a tap with no homepage.
        let output = #"""
        {"formulae":[],"casks":[
          {"token":"brewy","name":["Brewy"],"homepage":"https://brewy.example","version":"2.0",
           "outdated":true,"pinned":false,"deprecated":false,"disabled":false,"auto_updates":true},
          {"token":"vlc","name":["VLC"],"homepage":"https://vlc.example","version":"3.0",
           "outdated":true,"pinned":true,"deprecated":false,"disabled":false},
          {"token":"current","name":["Current"],"homepage":"https://current.example","version":"1.0",
           "outdated":false,"pinned":false,"deprecated":false,"disabled":false},
          {"token":"third","name":["Third"],"homepage":null,"version":"4.0",
           "outdated":true,"deprecated":false,"disabled":false}
        ]}
        """#
        let report = try XCTUnwrap(HomebrewOutdatedLoader.report(in: output))
        XCTAssertEqual(report.upgradable, ["brewy", "third"])
        XCTAssertEqual(report.pinned, ["vlc"])
        XCTAssertEqual(report.installedCasks.map(\.token), ["brewy", "vlc", "current"])
        XCTAssertEqual(report.installedCasks.first?.autoUpdates, true)

        XCTAssertEqual(
            HomebrewOutdatedLoader.report(in: #"{"formulae":[],"casks":[]}"#),
            HomebrewOutdatedReport(upgradable: [], pinned: [])
        )
        XCTAssertNil(HomebrewOutdatedLoader.report(in: "Error: brew is broken"))
    }
}
