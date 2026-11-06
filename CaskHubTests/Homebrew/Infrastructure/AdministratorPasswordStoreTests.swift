//
//  AdministratorPasswordStoreTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 06/11/2026.
//

@testable import CaskHub
import Security
import XCTest

final class AdministratorPasswordStoreTests: XCTestCase {
    func test_read_result_maps_keychain_statuses() {
        XCTAssertEqual(
            AdministratorPasswordReadResult(status: errSecSuccess, data: Data("pässwörd ✓".utf8)),
            .password("pässwörd ✓")
        )
        XCTAssertEqual(AdministratorPasswordReadResult(status: errSecUserCanceled, data: nil), .cancelled)
        XCTAssertEqual(AdministratorPasswordReadResult(status: errSecAuthFailed, data: nil), .authenticationFailed)
        XCTAssertEqual(AdministratorPasswordReadResult(status: errSecItemNotFound, data: nil), .notFound)
        XCTAssertEqual(AdministratorPasswordReadResult(status: errSecSuccess, data: nil), .failed(status: errSecSuccess))
        XCTAssertEqual(AdministratorPasswordReadResult(status: -34018, data: nil), .failed(status: -34018))
    }

    func test_store_is_available_only_with_entitlement_and_enrolled_biometry() {
        XCTAssertTrue(KeychainAdministratorPasswordStore(hasKeychainEntitlement: { true }, biometryEnrolled: { true }).isAvailable)
        XCTAssertFalse(KeychainAdministratorPasswordStore(hasKeychainEntitlement: { false }, biometryEnrolled: { true }).isAvailable)
        XCTAssertFalse(KeychainAdministratorPasswordStore(hasKeychainEntitlement: { true }, biometryEnrolled: { false }).isAvailable)
    }

    func test_unavailable_store_never_touches_the_keychain() {
        let store = KeychainAdministratorPasswordStore(hasKeychainEntitlement: { false }, biometryEnrolled: { true })
        XCTAssertFalse(store.savedPasswordExists())
        XCTAssertEqual(store.read(reason: "x"), .notFound)
        XCTAssertThrowsError(try store.save("secret"))
    }
}
