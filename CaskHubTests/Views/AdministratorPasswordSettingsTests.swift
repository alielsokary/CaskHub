//
//  AdministratorPasswordSettingsTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 06/11/2026.
//

@testable import CaskHub
import Synchronization
import XCTest

final class AdministratorPasswordSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "AdministratorPasswordSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var touchID: TouchIDAuthorizationSetting { TouchIDAuthorizationSetting(defaults: defaults) }

    @MainActor
    private func model(_ store: SettingsPasswordStoreSpy) -> AdministratorPasswordSettingsModel {
        AdministratorPasswordSettingsModel(store: store)
    }

    @MainActor
    func test_touch_id_section_hidden_without_keychain_access() async {
        touchID.setEnabled(true)
        let model = model(SettingsPasswordStoreSpy(available: false, keychainAccess: false, saved: true, touchID: touchID))

        await model.refresh()

        XCTAssertFalse(model.isAvailable)
        render(AdministratorPasswordSettingsSection(model: model), width: 460, height: 200)
    }

    @MainActor
    func test_touch_id_section_hidden_on_a_mac_without_touch_id() async {
        let model = model(SettingsPasswordStoreSpy(available: false, keychainAccess: true, saved: false, touchID: touchID))

        await model.refresh()

        XCTAssertFalse(model.isAvailable)
    }

    @MainActor
    func test_switch_stays_visible_while_on_so_it_can_be_turned_off() async {
        touchID.setEnabled(true)
        let store = SettingsPasswordStoreSpy(available: false, keychainAccess: true, saved: true, touchID: touchID)
        let model = model(store)

        await model.refresh()
        XCTAssertTrue(model.isAvailable)
        XCTAssertTrue(model.isEnabled)

        await model.setEnabled(false)
        XCTAssertEqual(store.deleteCount, 1)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(touchID.isEnabled)
    }

    @MainActor
    func test_turning_on_keeps_saved_password() async {
        let store = SettingsPasswordStoreSpy(available: true, keychainAccess: true, saved: false, touchID: touchID)
        let model = model(store)
        await model.refresh()
        XCTAssertTrue(model.isAvailable)
        XCTAssertFalse(model.isEnabled)
        render(AdministratorPasswordSettingsSection(model: model), width: 460, height: 200)

        await model.setEnabled(true)

        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(touchID.isEnabled)
        XCTAssertEqual(store.deleteCount, 0)
    }

    @MainActor
    func test_refresh_picks_up_a_change_made_in_the_password_prompt() async {
        let model = model(SettingsPasswordStoreSpy(available: true, keychainAccess: true, saved: false, touchID: touchID))
        await model.refresh()
        XCTAssertFalse(model.isEnabled)

        touchID.setEnabled(true)
        await model.refresh()

        XCTAssertTrue(model.isEnabled)
    }
}

private final class SettingsPasswordStoreSpy: AdministratorPasswordStoring {
    private struct State {
        var saved: Bool
        var deleteCount = 0
    }

    let isAvailable: Bool
    let hasKeychainAccess: Bool
    let touchID: TouchIDAuthorizationSetting
    private let state: Mutex<State>

    init(available: Bool, keychainAccess: Bool, saved: Bool, touchID: TouchIDAuthorizationSetting) {
        self.touchID = touchID
        isAvailable = available
        hasKeychainAccess = keychainAccess
        state = Mutex(State(saved: saved))
    }

    var deleteCount: Int { state.withLock { $0.deleteCount } }

    func savedPasswordExists() -> Bool { state.withLock { $0.saved } }

    func read(reason: String) -> AdministratorPasswordReadResult { .notFound }

    func save(_ password: String) throws { state.withLock { $0.saved = true } }

    func delete() {
        state.withLock {
            $0.saved = false
            $0.deleteCount += 1
        }
    }
}
