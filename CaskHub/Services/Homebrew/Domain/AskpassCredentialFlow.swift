//
//  AskpassCredentialFlow.swift
//  CaskHub
//
//  Created by Ali Elsokary on 06/11/2026.
//

import Foundation

nonisolated enum AskpassStep: Equatable, Sendable {
    case touchID
    case dialog(offerRemember: Bool, rememberChecked: Bool)
    case emit(String)
}

nonisolated enum AskpassStoreAction: Equatable, Sendable {
    case save
    case delete
    case none
}

nonisolated enum AskpassCredentialFlow {
    static func firstStep(attempt: Int?, storeAvailable: Bool, enabled: Bool, passwordSaved: Bool) -> AskpassStep {
        guard storeAvailable else { return .dialog(offerRemember: false, rememberChecked: false) }
        if attempt == 1, enabled, passwordSaved { return .touchID }
        return .dialog(offerRemember: true, rememberChecked: enabled)
    }

    static func step(after result: AdministratorPasswordReadResult, storeAvailable: Bool) -> AskpassStep {
        if case .password(let password) = result { return .emit(password) }
        return .dialog(offerRemember: storeAvailable, rememberChecked: storeAvailable && result != .notFound)
    }

    static func storeAction(remember: Bool, passwordSaved: Bool, storeAvailable: Bool) -> AskpassStoreAction {
        guard storeAvailable else { return .none }
        if remember { return .save }
        return passwordSaved ? .delete : .none
    }
}
