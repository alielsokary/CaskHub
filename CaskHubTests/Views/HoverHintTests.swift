//
//  HoverHintTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 15/11/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

final class HoverHintTests: XCTestCase {
    @MainActor
    func test_hint_width_wraps_long_text_and_keeps_short_text_on_one_line() {
        let long = "This app is managed by the Mac App Store, so Homebrew cannot uninstall it. Remove it in Finder."
        let longSize = fittingSize(long)
        let shortSize = fittingSize("From the foo/bar tap")

        XCTAssertLessThanOrEqual(longSize.width, 260)
        XCTAssertGreaterThan(longSize.height, shortSize.height * 2)
        XCTAssertLessThan(shortSize.width, 260)
    }

    @MainActor
    func test_hover_hint_renders_with_and_without_message() {
        render(Text(verbatim: "Badge").hoverHint("Explains the badge"), width: 120, height: 40)
        render(Text(verbatim: "Badge").hoverHint(nil), width: 120, height: 40)
    }

    @MainActor
    private func fittingSize(_ message: String) -> CGSize {
        NSHostingView(rootView: HintWidth(maxWidth: 260) { Text(verbatim: message) }).fittingSize
    }
}
