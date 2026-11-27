//
//  HomebrewMutationStep.swift
//  CaskHub
//
//  Created by Ali Elsokary on 05/10/2026.
//

import Foundation

enum HomebrewMutationRecoveryBehavior: Equatable {
    case finishMutation
    case continueSequence
}

enum HomebrewStepCancellation {
    case never
    case whileQueued
    case untilPerforming
}

struct HomebrewMutationStep {
    let arguments: [String]
    let environmentOverrides: [String: String]
    let lane: HomebrewLaneLimiter.Lane
    let cancellation: HomebrewStepCancellation
    let recoverIf: (() -> Bool)?
    let recoveryBehavior: HomebrewMutationRecoveryBehavior

    static func fetch(token: String, cancellation: HomebrewStepCancellation) -> HomebrewMutationStep {
        HomebrewMutationStep(
            arguments: ["fetch", "--cask", token],
            environmentOverrides: [:],
            lane: .download,
            cancellation: cancellation,
            recoverIf: nil,
            recoveryBehavior: .finishMutation
        )
    }

    static func exclusive(_ arguments: [String], cancellation: HomebrewStepCancellation) -> HomebrewMutationStep {
        HomebrewMutationStep(
            arguments: arguments,
            environmentOverrides: [:],
            lane: .exclusive,
            cancellation: cancellation,
            recoverIf: nil,
            recoveryBehavior: .finishMutation
        )
    }
}

struct HomebrewMutationSequenceRequest {
    let action: CaskAction
    let token: String
    let displayName: String
    let origin: CaskActionOrigin
    let steps: [HomebrewMutationStep]
    let context: HomebrewMutationContext
}

struct HomebrewMutationCallbacks {
    let refresh: () async -> Void
    let strandedCopyExists: () -> Bool
    let postconditionSatisfied: () -> Bool
    let conflictOccupant: (URL) -> AppConflictOccupant
}
