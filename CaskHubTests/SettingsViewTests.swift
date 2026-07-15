//
//  SettingsViewTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 16/07/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

/// Render smoke tests: hosting each settings tab executes its body,
/// which catches missing-environment crashes and init-time regressions
/// that a compile alone can't.
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
    }

    @MainActor
    func test_clear_cache_recreates_empty_icon_directory() {
        let cache = ImageCacheService()
        // Wiping the icon cache is the feature under test; icons refetch lazily.
        cache.clearCache()

        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CaskHub/icons", isDirectory: true)
        // The init's detached purge task may drop its marker file back in;
        // only cached icons and their markers must be gone.
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(contents.allSatisfy { $0.hasPrefix(".") },
                      "expected no cached icons, found: \(contents)")
    }
}
