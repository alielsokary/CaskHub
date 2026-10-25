//
//  CaskActionPresentation.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated enum CaskActionAlert: Equatable, Sendable {
    case adoption(CaskAdoptionRequest)
    case permission
    case homebrewMissing(message: String)
    case failure(CaskOperationFailure)

    static func make(operationState: CaskOperationState?) -> Self? {
        switch operationState {
        case let .awaitingAdoption(request):
            return .adoption(request)
        case .awaitingPermission:
            return .permission
        case let .failed(failure) where failure.kind == .homebrewMissing:
            return .homebrewMissing(message: failure.message)
        case let .failed(failure):
            return .failure(failure)
        case .queued, .running, nil:
            return nil
        }
    }
}

nonisolated struct CaskActionPresentation: Equatable, Sendable {
    let localState: CaskLocalState
    let homebrewInstallation: LocalCaskInstallation?
    let operationState: CaskOperationState?
    let isHomebrewMutationBlocked: Bool

    var activeAction: CaskAction? {
        operationState?.action
    }

    var progress: CaskOperationProgress? {
        operationState?.progress
    }

    var isCanceling: Bool {
        operationState?.cancellationRequested == true
    }

    var canCancel: Bool {
        operationState?.canCancel == true
    }

    var isBusy: Bool {
        activeAction != nil || isHomebrewMutationBlocked
    }

}

extension CaskRetirement {
    /// Whole sentences, so each piece translates on its own.
    func summary(isInstalled: Bool) -> String {
        switch self {
        case let .deprecated(reason, _, plannedDisableDate, replacement):
            return Self.sentences(
                String(localized: .caskRetirementDeprecatedHeadline),
                reason.map(Self.reasonText),
                plannedDisableDate.map { String(localized: .caskRetirementPlannedDisable(Self.dayText($0))) },
                replacement.map(Self.replacementText),
                String(localized: .caskRetirementDeprecatedNote)
            )
        case let .disabled(reason, disabledOn, replacement):
            return Self.sentences(
                String(localized: .caskRetirementDisabledHeadline),
                reason.map(Self.reasonText),
                disabledOn.map { String(localized: .caskRetirementDisabledOn(Self.dayText($0))) },
                replacement.map(Self.replacementText),
                isInstalled
                    ? String(localized: .caskRetirementDisabledInstalled)
                    : String(localized: .caskRetirementDisabledNotInstalled)
            )
        case .removedFromHomebrew:
            return Self.sentences(
                String(localized: .caskRetirementRemovedHeadline),
                String(localized: .caskRetirementRemovedInstalled)
            )
        }
    }

    static func reasonText(_ reason: String) -> String {
        switch reason {
        case "discontinued": String(localized: .caskRetirementReasonDiscontinued)
        case "moved_to_mas": String(localized: .caskRetirementReasonMovedToMas)
        case "no_longer_available": String(localized: .caskRetirementReasonNoLongerAvailable)
        case "no_longer_meets_criteria": String(localized: .caskRetirementReasonNoLongerMeetsCriteria)
        case "unmaintained": String(localized: .caskRetirementReasonUnmaintained)
        case "fails_gatekeeper_check", "unsigned": String(localized: .caskRetirementReasonFailsGatekeeperCheck)
        case "unreachable": String(localized: .caskRetirementReasonUnreachable)
        default: String(localized: .caskRetirementReasonOther(reason))
        }
    }

    /// Homebrew dates are calendar days at GMT midnight; local time would shift them a day west of GMT.
    static func dayText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
    }

    static func replacementText(_ replacement: CaskReplacement) -> String {
        switch replacement {
        case let .cask(token): String(localized: .caskRetirementReplacementCask(token))
        case let .formula(token): String(localized: .caskRetirementReplacementFormula(token))
        }
    }

    private static func sentences(_ parts: String?...) -> String {
        parts.compactMap { $0 }.joined(separator: " ")
    }
}
