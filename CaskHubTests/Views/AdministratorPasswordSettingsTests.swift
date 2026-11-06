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
    @MainActor
    func test_touch_id_section_hidden_when_store_unavailable() async {
        let model = AdministratorPasswordSettingsModel(store: SettingsPasswordStoreSpy(available: false, saved: true))

        await model.refresh()

        XCTAssertFalse(model.isAvailable)
        XCTAssertFalse(model.hasSavedPassword)
        render(AdministratorPasswordSettingsSection(model: model), width: 460, height: 200)
    }

    @MainActor
    func test_forget_deletes_and_disables_button() async {
        let store = SettingsPasswordStoreSpy(available: true, saved: true)
        let model = AdministratorPasswordSettingsModel(store: store)
        await model.refresh()
        XCTAssertTrue(model.hasSavedPassword)
        render(AdministratorPasswordSettingsSection(model: model), width: 460, height: 200)

        await model.forget()

        XCTAssertEqual(store.deleteCount, 1)
        XCTAssertFalse(model.hasSavedPassword)
    }

    @MainActor
    func test_refresh_reflects_saved_password() async {
        let store = SettingsPasswordStoreSpy(available: true, saved: false)
        let model = AdministratorPasswordSettingsModel(store: store)

        await model.refresh()
        XCTAssertTrue(model.isAvailable)
        XCTAssertFalse(model.hasSavedPassword)

        store.setSaved(true)
        await model.refresh()
        XCTAssertTrue(model.hasSavedPassword)
    }
}

private final class SettingsPasswordStoreSpy: AdministratorPasswordStoring {
    private struct State {
        var saved: Bool
        var deleteCount = 0
    }

    let isAvailable: Bool
    private let state: Mutex<State>

    init(available: Bool, saved: Bool) {
        isAvailable = available
        state = Mutex(State(saved: saved))
    }

    var deleteCount: Int { state.withLock { $0.deleteCount } }

    func setSaved(_ saved: Bool) { state.withLock { $0.saved = saved } }

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
