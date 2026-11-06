//
//  AskpassTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 06/11/2026.
//

@testable import CaskHub
import XCTest

final class AskpassTests: XCTestCase {
    func test_saved_password_is_returned_after_touch_id_without_a_dialog() {
        let store = FakePasswordStore(saved: true, readResult: .password("pw"))
        let dialog = FakeDialog(response: nil)

        let outcome = resolve(attempt: 1, store: store, dialog: dialog)

        XCTAssertEqual(outcome, .password("pw"))
        XCTAssertTrue(dialog.requests.isEmpty)
        XCTAssertEqual(store.readReasons, ["authorize changes for “zoom”"])
        XCTAssertTrue(store.writes.isEmpty)
    }

    func test_touch_id_cancel_falls_back_to_dialog_and_keeps_saved_password() {
        let store = FakePasswordStore(saved: true, readResult: .cancelled)
        let dialog = FakeDialog(response: AskpassDialogResponse(password: "typed", remember: true))

        let outcome = resolve(attempt: 1, store: store, dialog: dialog)

        XCTAssertEqual(outcome, .password("typed"))
        XCTAssertEqual(
            dialog.requests,
            [AskpassDialogRequest(token: "zoom", offerRemember: true, rememberChecked: true, previousAttemptRejected: false)]
        )
        XCTAssertEqual(store.writes, [.save("typed")])
    }

    func test_retry_overwrites_stale_password() {
        let store = FakePasswordStore(saved: true, readResult: .password("stale"))
        let dialog = FakeDialog(response: AskpassDialogResponse(password: "new", remember: true))

        let outcome = resolve(attempt: 2, store: store, dialog: dialog)

        XCTAssertEqual(outcome, .password("new"))
        XCTAssertTrue(store.readReasons.isEmpty)
        XCTAssertEqual(
            dialog.requests,
            [AskpassDialogRequest(token: "zoom", offerRemember: true, rememberChecked: true, previousAttemptRejected: true)]
        )
        XCTAssertEqual(store.writes, [.save("new")])
    }

    func test_unticking_remember_forgets_saved_password() {
        let store = FakePasswordStore(saved: true, readResult: .password("stale"))
        let dialog = FakeDialog(response: AskpassDialogResponse(password: "new", remember: false))

        XCTAssertEqual(resolve(attempt: 2, store: store, dialog: dialog), .password("new"))
        XCTAssertEqual(store.writes, [.delete])
    }

    func test_dialog_cancel_is_cancelled() {
        let store = FakePasswordStore(saved: false, readResult: .notFound)
        let dialog = FakeDialog(response: nil)

        XCTAssertEqual(resolve(attempt: 1, store: store, dialog: dialog), .cancelled)
        XCTAssertTrue(store.writes.isEmpty)
    }

    func test_save_failure_still_returns_the_password() {
        let store = FakePasswordStore(saved: false, readResult: .notFound, saveFails: true)
        let dialog = FakeDialog(response: AskpassDialogResponse(password: "typed", remember: true))

        XCTAssertEqual(resolve(attempt: 1, store: store, dialog: dialog), .password("typed"))
    }

    func test_next_attempt_counts_and_handles_missing_marker() throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("askpass-attempts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }

        XCTAssertEqual(Askpass.nextAttempt(marker: marker), 1)
        XCTAssertEqual(Askpass.nextAttempt(marker: marker), 2)
        XCTAssertNil(Askpass.nextAttempt(marker: nil))
        XCTAssertNil(Askpass.nextAttempt(marker: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/attempts")))
    }

    func test_password_rejected_by_login_check_is_not_saved() {
        let store = FakePasswordStore(saved: false, readResult: .notFound)
        let dialog = FakeDialog(response: AskpassDialogResponse(password: "typo", remember: true))

        let outcome = resolve(attempt: 1, store: store, dialog: dialog, accepts: false)

        XCTAssertEqual(outcome, .password("typo"))
        XCTAssertTrue(store.writes.isEmpty)
    }

    func test_first_prompt_does_not_claim_a_rejected_password() {
        let store = FakePasswordStore(saved: false, readResult: .notFound)
        let dialog = FakeDialog(response: nil)

        _ = resolve(attempt: 1, store: store, dialog: dialog)
        _ = resolve(attempt: nil, store: store, dialog: dialog)

        XCTAssertEqual(dialog.requests.map(\.previousAttemptRejected), [false, false])
    }

    private func resolve(
        attempt: Int?, store: FakePasswordStore, dialog: FakeDialog, accepts: Bool = true
    ) -> AskpassOutcome {
        Askpass.resolve(
            token: "zoom", attempt: attempt, store: store,
            passwordAccepted: { _ in accepts }, presentDialog: { dialog.present($0) }
        )
    }
}

private final class FakeDialog {
    private let response: AskpassDialogResponse?
    private(set) var requests: [AskpassDialogRequest] = []

    init(response: AskpassDialogResponse?) {
        self.response = response
    }

    func present(_ request: AskpassDialogRequest) -> AskpassDialogResponse? {
        requests.append(request)
        return response
    }
}

private final class FakePasswordStore: AdministratorPasswordStoring, @unchecked Sendable {
    enum Write: Equatable {
        case save(String)
        case delete
    }

    let isAvailable = true
    let hasKeychainAccess = true
    private let saved: Bool
    private let readResult: AdministratorPasswordReadResult
    private let saveFails: Bool
    private(set) var readReasons: [String] = []
    private(set) var writes: [Write] = []

    init(saved: Bool, readResult: AdministratorPasswordReadResult, saveFails: Bool = false) {
        self.saved = saved
        self.readResult = readResult
        self.saveFails = saveFails
    }

    func savedPasswordExists() -> Bool { saved }

    func read(reason: String) -> AdministratorPasswordReadResult {
        readReasons.append(reason)
        return readResult
    }

    func save(_ password: String) throws {
        writes.append(.save(password))
        if saveFails { throw AdministratorPasswordStoreError.keychain(status: -1) }
    }

    func delete() {
        writes.append(.delete)
    }
}

final class AskpassUnreachableStepTests: XCTestCase {
    func test_dialog_request_falls_back_to_dialog_for_any_non_password_step() {
        XCTAssertEqual(
            Askpass.dialogRequest(for: .touchID, token: "zoom", attempt: 1, storeAvailable: true, passwordSaved: true),
            AskpassDialogRequest(token: "zoom", offerRemember: true, rememberChecked: true, previousAttemptRejected: false)
        )
        XCTAssertNil(Askpass.dialogRequest(for: .emit("pw"), token: "zoom", attempt: 1, storeAvailable: true, passwordSaved: true))
    }
}
