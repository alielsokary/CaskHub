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
    private func model(_ store: SettingsPasswordStoreSpy, accepts: Bool = true) -> AdministratorPasswordSettingsModel {
        AdministratorPasswordSettingsModel(store: store, passwordAccepted: { _ in accepts })
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

        await model.disable()
        XCTAssertEqual(store.deleteCount, 1)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(touchID.isEnabled)
    }

    @MainActor
    func test_turning_on_saves_the_accepted_password() async {
        let store = SettingsPasswordStoreSpy(available: true, keychainAccess: true, saved: false, touchID: touchID)
        let model = model(store)
        await model.refresh()
        XCTAssertTrue(model.isAvailable)
        XCTAssertFalse(model.isEnabled)
        render(AdministratorPasswordSettingsSection(model: model), width: 460, height: 200)

        let result = await model.enable(password: "secret")

        XCTAssertEqual(result, .enabled)
        XCTAssertEqual(store.savedPassword, "secret")
        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(touchID.isEnabled)
    }

    @MainActor
    func test_wrong_password_keeps_the_switch_off() async {
        let store = SettingsPasswordStoreSpy(available: true, keychainAccess: true, saved: false, touchID: touchID)
        let model = model(store, accepts: false)

        let result = await model.enable(password: "typo")

        XCTAssertEqual(result, .rejected)
        XCTAssertNil(store.savedPassword)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(touchID.isEnabled)
    }

    @MainActor
    func test_keychain_failure_keeps_the_switch_off() async {
        let store = SettingsPasswordStoreSpy(
            available: true, keychainAccess: true, saved: false, touchID: touchID, saveFails: true
        )
        let model = model(store)

        let result = await model.enable(password: "secret")

        XCTAssertEqual(result, .failed)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(touchID.isEnabled)
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
        var savedPassword: String?
        var deleteCount = 0
    }

    let isAvailable: Bool
    let hasKeychainAccess: Bool
    let touchID: TouchIDAuthorizationSetting
    private let saveFails: Bool
    private let state: Mutex<State>

    init(
        available: Bool, keychainAccess: Bool, saved: Bool, touchID: TouchIDAuthorizationSetting, saveFails: Bool = false
    ) {
        self.touchID = touchID
        self.saveFails = saveFails
        isAvailable = available
        hasKeychainAccess = keychainAccess
        state = Mutex(State(saved: saved))
    }

    var deleteCount: Int { state.withLock { $0.deleteCount } }

    func savedPasswordExists() -> Bool { state.withLock { $0.saved } }

    func read(reason: String) -> AdministratorPasswordReadResult { .notFound }

    var savedPassword: String? { state.withLock { $0.savedPassword } }

    func save(_ password: String) throws {
        if saveFails { throw AdministratorPasswordStoreError.keychain(status: -1) }
        state.withLock {
            $0.saved = true
            $0.savedPassword = password
        }
    }

    func delete() {
        state.withLock {
            $0.saved = false
            $0.deleteCount += 1
        }
    }
}
