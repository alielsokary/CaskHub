//
//  SettingsViewTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 16/07/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

final class SettingsViewTests: XCTestCase {
    @MainActor
    private func render(_ view: some View) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 480)
        hosting.layoutSubtreeIfNeeded()
    }

    @MainActor
    func test_settings_tabs_render() {
        render(AppearanceSettingsView())
        render(PrivacySettingsView())
        render(AboutSettingsView())
        render(
            GeneralSettingsView()
                .environment(UpdaterService())
                .environment(ImageCacheService())
        )
        render(
            HomebrewSettingsView()
                .environment(LocalHomebrewService())
        )
    }

    @MainActor
    func test_clear_cache_recreates_empty_icon_directory() {
        let cache = ImageCacheService()
        cache.clearCache()

        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CaskHub/icons", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(contents.allSatisfy { $0.hasPrefix(".") },
                      "expected no cached icons, found: \(contents)")
    }

    @MainActor
    func test_theme_preview_assets_are_bundled() {
        for theme in AppTheme.allCases {
            XCTAssertNotNil(theme.previewImage, "missing theme preview for \(theme.rawValue)")
        }
    }
}
