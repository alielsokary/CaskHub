//
//  HelpViewTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 09/08/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

final class HelpViewTests: XCTestCase {
    func test_help_topics_cover_the_core_caskhub_workflows() {
        XCTAssertEqual(
            HelpTopic.allCases,
            [
                .gettingStarted,
                .homebrew,
                .installAndUpdate,
                .adoption,
                .permissions,
                .troubleshooting
            ]
        )
    }

    @MainActor
    func test_help_center_renders_every_topic() {
        for topic in HelpTopic.allCases {
            let view = CaskHubHelpView(
                selection: .constant(topic),
                settingsSelection: .constant(.general),
                navigateToCatalog: { _ in }
            )
            .environment(LocalHomebrewService())
            let hosting = NSHostingView(rootView: AnyView(view))
            hosting.frame = NSRect(x: 0, y: 0, width: 880, height: 620)
            hosting.layoutSubtreeIfNeeded()
        }
    }
}
