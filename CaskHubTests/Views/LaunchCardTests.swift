//
//  LaunchCardTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 04/10/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

@MainActor
final class LaunchCardTests: XCTestCase {
    private func resolve(
        _ defaults: UserDefaults,
        current: String,
        hasPriorInstall: Bool = true
    ) -> LaunchCard? {
        LaunchCardGate.resolve(
            in: defaults,
            currentVersion: current,
            hasPriorInstall: hasPriorInstall,
            latestVersion: "0.9.0"
        )
    }

    private func lastSeen(_ defaults: UserDefaults) -> String? {
        defaults.string(forKey: LaunchCardGate.lastSeenVersionKey)
    }

    func test_fresh_install_shows_welcome_once() {
        let defaults = makeScratchDefaults()

        XCTAssertEqual(resolve(defaults, current: "0.9.0", hasPriorInstall: false), .welcome)
        XCTAssertEqual(lastSeen(defaults), "0.9.0")
        XCTAssertNil(resolve(defaults, current: "0.9.0"))
    }

    func test_upgrade_from_build_without_gate_shows_whats_new_once() {
        let defaults = makeScratchDefaults()

        XCTAssertEqual(resolve(defaults, current: "0.9.0"), .whatsNew)
        XCTAssertEqual(lastSeen(defaults), "0.9.0")
        XCTAssertNil(resolve(defaults, current: "0.9.0"))
    }

    func test_patch_release_after_seen_entry_stays_silent() {
        let defaults = makeScratchDefaults()
        defaults.set("0.9.0", forKey: LaunchCardGate.lastSeenVersionKey)

        XCTAssertNil(resolve(defaults, current: "0.9.1"))
        XCTAssertEqual(lastSeen(defaults), "0.9.1")
    }

    func test_update_that_skips_the_entry_version_still_shows_it() {
        let defaults = makeScratchDefaults()
        defaults.set("0.8.3", forKey: LaunchCardGate.lastSeenVersionKey)

        XCTAssertEqual(resolve(defaults, current: "0.9.1"), .whatsNew)
        XCTAssertEqual(lastSeen(defaults), "0.9.1")
    }

    func test_entry_ahead_of_the_build_waits_for_its_version() {
        let defaults = makeScratchDefaults()

        XCTAssertNil(resolve(defaults, current: "0.8.4"))
        XCTAssertEqual(lastSeen(defaults), "0.8.4")
        XCTAssertEqual(resolve(defaults, current: "0.9.0"), .whatsNew)
    }

    func test_unparseable_stored_version_stays_silent_and_heals() {
        let defaults = makeScratchDefaults()
        defaults.set("garbage", forKey: LaunchCardGate.lastSeenVersionKey)

        XCTAssertNil(resolve(defaults, current: "0.9.0"))
        XCTAssertEqual(lastSeen(defaults), "0.9.0")
    }

    func test_preview_forces_a_card_without_recording() {
        let defaults = makeScratchDefaults()

        defaults.set("welcome", forKey: LaunchCardGate.previewKey)
        XCTAssertEqual(resolve(defaults, current: "0.9.0"), .welcome)

        defaults.set("whatsNew", forKey: LaunchCardGate.previewKey)
        XCTAssertEqual(resolve(defaults, current: "0.8.3"), .whatsNew)

        XCTAssertNil(lastSeen(defaults))
    }

    func test_whats_new_rows_read_their_text_from_the_whats_new_table() {
        XCTAssertFalse(WhatsNewRelease.latest.features.isEmpty)
        for feature in WhatsNewRelease.latest.features {
            for resource in [feature.title, feature.detail] {
                XCTAssertEqual(resource.table, "WhatsNew")
                XCTAssertNotEqual(String(localized: resource), resource.key)
            }
        }
    }

    func test_cards_render_in_both_styles() {
        let style = AppStyle.current
        defer { AppStyle.current = style }

        for style in AppStyle.allCases {
            AppStyle.current = style
            render(LaunchCardView(card: .whatsNew), width: 480, height: 600)
            render(LaunchCardView(card: .welcome), width: 600, height: 480)
            for page in WelcomePage.allCases {
                render(WelcomeCardView(page: page), width: 600, height: 480)
            }
        }
    }

    func test_welcome_look_page_offers_the_match_system_toggle_without_scrolling() throws {
        let style = AppStyle.current
        defer { AppStyle.current = style }
        let suite = "welcome-look-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for style in AppStyle.allCases {
            for theme in AppTheme.allCases {
                AppStyle.current = style
                defaults.set(theme.rawValue, forKey: "appTheme")
                let host = NSHostingView(rootView: WelcomeCardView(page: .look).defaultAppStorage(defaults))
                host.frame = NSRect(x: 0, y: 0, width: 600, height: 480)
                host.layoutSubtreeIfNeeded()

                let switches = host.descendants(of: NSSwitch.self)
                XCTAssertEqual(switches.count, 3, "two privacy switches plus match system, \(style) \(theme)")
                XCTAssertTrue(host.descendants(of: NSScrollView.self).isEmpty, "\(style) \(theme)")
            }
        }
    }

    func test_welcome_match_system_toggle_pins_and_releases_the_mode() throws {
        let suite = "welcome-look-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AppTheme.light.rawValue, forKey: "appTheme")

        let host = NSHostingView(rootView: WelcomeCardView(page: .look).defaultAppStorage(defaults))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 480)
        host.layoutSubtreeIfNeeded()
        let off = host.descendants(of: NSSwitch.self).filter { $0.state == .off }
        let toggle = try XCTUnwrap(off.first)
        XCTAssertEqual(off.count, 1)

        toggle.performClick(nil)
        XCTAssertEqual(defaults.string(forKey: "appTheme"), AppTheme.system.rawValue)

        host.layoutSubtreeIfNeeded()
        toggle.performClick(nil)
        XCTAssertTrue([AppTheme.light, .dark].map(\.rawValue).contains(defaults.string(forKey: "appTheme")))
    }
}

private extension NSView {
    func descendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { [$0 as? T].compactMap(\.self) + $0.descendants(of: type) }
    }
}
