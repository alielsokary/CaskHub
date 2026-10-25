//
//  CaskRetirement.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/10/2026.
//

import Foundation

nonisolated enum CaskReplacement: Equatable, Sendable {
    case cask(String)
    case formula(String)
}

nonisolated enum CaskRetirement: Equatable, Sendable {
    case deprecated(reason: String?, deprecatedOn: Date?, plannedDisableDate: Date?, replacement: CaskReplacement?)
    case disabled(reason: String?, disabledOn: Date?, replacement: CaskReplacement?)
    case removedFromHomebrew

    /// Homebrew still installs and upgrades deprecated casks.
    var blocksInstall: Bool {
        if case .deprecated = self { return false }
        return true
    }
}

/// The `deprecate!` and `disable!` fields one cask or platform variant declares.
nonisolated struct CaskRetirementFields: Hashable, Sendable {
    let deprecated: Bool
    let deprecationDate: String?
    let deprecationReason: String?
    let deprecationReplacementCask: String?
    let deprecationReplacementFormula: String?
    let disabled: Bool
    let disableDate: String?
    let disableReason: String?
    let disableReplacementCask: String?
    let disableReplacementFormula: String?

    var retirement: CaskRetirement? {
        let deprecationReplacement = Self.replacement(deprecationReplacementCask, deprecationReplacementFormula)
        let disableReplacement = Self.replacement(disableReplacementCask, disableReplacementFormula)
        if disabled {
            return .disabled(
                reason: disableReason ?? deprecationReason,
                disabledOn: Self.day(disableDate),
                replacement: disableReplacement ?? deprecationReplacement
            )
        }
        guard deprecated else { return nil }
        let deprecatedOn = Self.day(deprecationDate)
        // Homebrew disables a deprecated cask 12 months after deprecation unless `disable!` names a date.
        let plannedDisableDate = Self.day(disableDate)
            ?? deprecatedOn.flatMap { Self.calendar.date(byAdding: .month, value: 12, to: $0) }
        return .deprecated(
            reason: deprecationReason ?? disableReason,
            deprecatedOn: deprecatedOn,
            plannedDisableDate: plannedDisableDate,
            replacement: deprecationReplacement ?? disableReplacement
        )
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private static func day(_ iso: String?) -> Date? {
        iso.flatMap { try? Date($0, strategy: Date.ISO8601FormatStyle().year().month().day()) }
    }

    private static func replacement(_ cask: String?, _ formula: String?) -> CaskReplacement? {
        cask.map(CaskReplacement.cask) ?? formula.map(CaskReplacement.formula)
    }
}

extension Cask {
    var retirementFields: CaskRetirementFields {
        CaskRetirementFields(
            deprecated: deprecated,
            deprecationDate: deprecationDate,
            deprecationReason: deprecationReason,
            deprecationReplacementCask: deprecationReplacementCask,
            deprecationReplacementFormula: deprecationReplacementFormula,
            disabled: disabled,
            disableDate: disableDate,
            disableReason: disableReason,
            disableReplacementCask: disableReplacementCask,
            disableReplacementFormula: disableReplacementFormula
        )
    }

    func retirement(for platform: CaskPlatform?) -> CaskRetirement? {
        if provenance == .installedReceipt {
            return tap == "homebrew/cask" ? .removedFromHomebrew : nil
        }
        if let tag = platform?.tag, let variation = variations?[tag] {
            return variation.retirementFields(inheriting: retirementFields).retirement
        }
        return retirementFields.retirement
    }
}
