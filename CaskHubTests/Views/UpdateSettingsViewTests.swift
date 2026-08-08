//
//  UpdateSettingsViewTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 02/08/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

final class UpdateSettingsViewTests: XCTestCase {
    @MainActor
    func test_update_settings_and_about_support_render() {
        render(
            UpdateSettingsView()
                .environment(UpdaterService())
        )
        render(AboutSettingsView())
    }

    @MainActor
    func test_about_support_uses_caskhub_issue_chooser() {
        XCTAssertEqual(
            CaskHubLinks.issues.absoluteString,
            "https://github.com/alielsokary/CaskHub/issues/new/choose"
        )
    }

    @MainActor
    private func render(_ view: some View) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 480)
        hosting.layoutSubtreeIfNeeded()
    }
}
