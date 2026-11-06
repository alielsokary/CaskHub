//
//  AskpassCredentialFlowTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 06/11/2026.
//

@testable import CaskHub
import XCTest

final class AskpassCredentialFlowTests: XCTestCase {
    func test_first_call_with_saved_password_uses_touch_id() {
        XCTAssertEqual(AskpassCredentialFlow.firstStep(attempt: 1, storeAvailable: true, passwordSaved: true), .touchID)
    }

    func test_first_call_without_saved_password_offers_unchecked_remember() {
        XCTAssertEqual(
            AskpassCredentialFlow.firstStep(attempt: 1, storeAvailable: true, passwordSaved: false),
            .dialog(offerRemember: true, rememberChecked: false)
        )
    }

    func test_retry_after_wrong_password_skips_keychain_and_keeps_remember_checked() {
        XCTAssertEqual(
            AskpassCredentialFlow.firstStep(attempt: 2, storeAvailable: true, passwordSaved: true),
            .dialog(offerRemember: true, rememberChecked: true)
        )
    }

    func test_missing_attempt_marker_skips_keychain() {
        XCTAssertEqual(
            AskpassCredentialFlow.firstStep(attempt: nil, storeAvailable: true, passwordSaved: true),
            .dialog(offerRemember: true, rememberChecked: true)
        )
    }

    func test_unavailable_store_shows_plain_dialog() {
        XCTAssertEqual(
            AskpassCredentialFlow.firstStep(attempt: 1, storeAvailable: false, passwordSaved: true),
            .dialog(offerRemember: false, rememberChecked: false)
        )
    }

    func test_touch_id_outcomes() {
        XCTAssertEqual(AskpassCredentialFlow.step(after: .password("pw"), storeAvailable: true), .emit("pw"))
        let failures: [AdministratorPasswordReadResult] = [.cancelled, .authenticationFailed, .notFound, .failed(status: -26276)]
        for result in failures {
            XCTAssertEqual(
                AskpassCredentialFlow.step(after: result, storeAvailable: true),
                .dialog(offerRemember: true, rememberChecked: result != .notFound),
                "\(result)"
            )
        }
    }

    func test_store_actions() {
        XCTAssertEqual(AskpassCredentialFlow.storeAction(remember: true, passwordSaved: false, storeAvailable: true), .save)
        XCTAssertEqual(AskpassCredentialFlow.storeAction(remember: true, passwordSaved: true, storeAvailable: true), .save)
        XCTAssertEqual(AskpassCredentialFlow.storeAction(remember: false, passwordSaved: true, storeAvailable: true), .delete)
        XCTAssertEqual(AskpassCredentialFlow.storeAction(remember: false, passwordSaved: false, storeAvailable: true), .none)
        XCTAssertEqual(AskpassCredentialFlow.storeAction(remember: false, passwordSaved: true, storeAvailable: false), .none)
    }
}
