//
//  AdministratorPasswordStore.swift
//  CaskHub
//
//  Created by Ali Elsokary on 06/11/2026.
//

import Foundation
import LocalAuthentication
import Security

nonisolated enum AdministratorPasswordReadResult: Equatable, Sendable {
    case password(String)
    case cancelled
    case authenticationFailed
    case notFound
    case failed(status: OSStatus)

    init(status: OSStatus, data: Data?) {
        switch status {
        case errSecSuccess:
            if let data, let password = String(data: data, encoding: .utf8) {
                self = .password(password)
            } else {
                self = .failed(status: status)
            }
        case errSecUserCanceled: self = .cancelled
        case errSecAuthFailed: self = .authenticationFailed
        case errSecItemNotFound: self = .notFound
        default: self = .failed(status: status)
        }
    }
}

nonisolated enum AdministratorPasswordStoreError: Error, Equatable, Sendable {
    case unavailable
    case keychain(status: OSStatus)
}

nonisolated struct TouchIDAuthorizationSetting: Sendable {
    private static let key = "authorizeWithTouchID"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.key) }

    func setEnabled(_ enabled: Bool) { defaults.set(enabled, forKey: Self.key) }
}

nonisolated protocol AdministratorPasswordStoring: Sendable {
    var isAvailable: Bool { get }
    var hasKeychainAccess: Bool { get }
    var touchID: TouchIDAuthorizationSetting { get }
    func savedPasswordExists() -> Bool
    func read(reason: String) -> AdministratorPasswordReadResult
    func save(_ password: String) throws
    func delete()
}

nonisolated struct KeychainAdministratorPasswordStore: AdministratorPasswordStoring {
    private static let service = "com.mag.caskhub.administrator-password"

    let touchID: TouchIDAuthorizationSetting
    private let hasKeychainEntitlement: @Sendable () -> Bool
    private let biometryEnrolled: @Sendable () -> Bool

    init(
        hasKeychainEntitlement: @escaping @Sendable () -> Bool = KeychainAdministratorPasswordStore.processHasKeychainEntitlement,
        biometryEnrolled: @escaping @Sendable () -> Bool = KeychainAdministratorPasswordStore.deviceHasEnrolledBiometry,
        touchID: TouchIDAuthorizationSetting = TouchIDAuthorizationSetting()
    ) {
        self.touchID = touchID
        self.hasKeychainEntitlement = hasKeychainEntitlement
        self.biometryEnrolled = biometryEnrolled
    }

    var isAvailable: Bool {
        hasKeychainEntitlement() && biometryEnrolled()
    }

    var hasKeychainAccess: Bool {
        hasKeychainEntitlement()
    }

    func savedPasswordExists() -> Bool {
        guard hasKeychainAccess else { return false }
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    func read(reason: String) -> AdministratorPasswordReadResult {
        guard isAvailable else { return .notFound }
        let context = LAContext()
        context.localizedReason = reason
        var query = baseQuery
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return AdministratorPasswordReadResult(status: status, data: result as? Data)
    }

    func save(_ password: String) throws {
        guard isAvailable else { throw AdministratorPasswordStoreError.unavailable }
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil
        ) else {
            throw AdministratorPasswordStoreError.keychain(status: errSecParam)
        }
        delete()
        var attributes = baseQuery
        attributes[kSecAttrAccessControl as String] = access
        attributes[kSecValueData as String] = Data(password.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw AdministratorPasswordStoreError.keychain(status: status) }
    }

    func delete() {
        guard hasKeychainAccess else { return }
        SecItemDelete(baseQuery as CFDictionary)
    }

    static func processHasKeychainEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) != nil
    }

    static func deviceHasEnrolledBiometry() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: NSUserName(),
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}
