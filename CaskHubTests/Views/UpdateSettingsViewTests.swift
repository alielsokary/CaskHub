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
    func test_sparkle_modal_alert_hooks_pause_and_resume_hang_tracking() {
        let spy = SpyCrashReporterProvider()
        let original = CrashReporter.provider
        let wasActive = CrashReporter.isApplicationActive
        let pauseDepth = CrashReporter.hangTrackingPauseDepth
        defer {
            CrashReporter.provider = original
            CrashReporter.isApplicationActive = wasActive
            CrashReporter.hangTrackingPauseDepth = pauseDepth
        }
        CrashReporter.provider = spy
        CrashReporter.isApplicationActive = true
        CrashReporter.hangTrackingPauseDepth = 0

        let updater = UpdaterService()
        updater.standardUserDriverWillShowModalAlert()
        updater.standardUserDriverDidShowModalAlert()

        XCTAssertEqual(spy.hangTrackingEvents, ["pause", "resume"])
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
