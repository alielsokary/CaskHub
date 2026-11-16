//
//  CaskUpdateTarget.swift
//  CaskHub
//
//  Created by Ali Elsokary on 05/10/2026.
//

import Foundation

nonisolated struct CaskPlatform: Equatable, Sendable {
    let tag: String
}

nonisolated struct CaskUpdateTarget: Equatable, Sendable {
    let version: String
    let autoUpdates: Bool?
}

/// Homebrew variants replace complete fields, including explicit nulls.
/// Only fields used for update eligibility and retirement status are retained here.
nonisolated struct CaskUpdateVariation: Decodable, Hashable, Sendable {
    private let version: String?
    private let autoUpdates: Bool?
    private let disabled: Bool?
    private let deprecated: Bool?
    /// The `deprecate!` and `disable!` text fields this variant replaces; an explicit null is a key without a value.
    private let retirementText: [CodingKeys: String]
    private let fields: Set<CodingKeys>

    private enum CodingKeys: String, CodingKey {
        case version, autoUpdates, disabled, deprecated
        case deprecationDate, deprecationReason, deprecationReplacementCask, deprecationReplacementFormula
        case disableDate, disableReason, disableReplacementCask, disableReplacementFormula
    }

    private static let retirementTextKeys: [CodingKeys] = [
        .deprecationDate, .deprecationReason, .deprecationReplacementCask, .deprecationReplacementFormula,
        .disableDate, .disableReason, .disableReplacementCask, .disableReplacementFormula
    ]

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fields = Set(values.allKeys)
        version = try values.decodeIfPresent(String.self, forKey: .version)
        autoUpdates = try values.decodeIfPresent(Bool.self, forKey: .autoUpdates)
        disabled = try values.decodeIfPresent(Bool.self, forKey: .disabled)
        deprecated = try values.decodeIfPresent(Bool.self, forKey: .deprecated)
        retirementText = try Self.retirementTextKeys.reduce(into: [:]) { text, key in
            text[key] = try values.decodeIfPresent(String.self, forKey: key)
        }
    }

    func retirementFields(inheriting base: CaskRetirementFields) -> CaskRetirementFields {
        func text(_ key: CodingKeys, _ inherited: String?) -> String? {
            fields.contains(key) ? retirementText[key] : inherited
        }
        return CaskRetirementFields(
            deprecated: fields.contains(.deprecated) ? deprecated == true : base.deprecated,
            deprecationDate: text(.deprecationDate, base.deprecationDate),
            deprecationReason: text(.deprecationReason, base.deprecationReason),
            deprecationReplacementCask: text(.deprecationReplacementCask, base.deprecationReplacementCask),
            deprecationReplacementFormula: text(.deprecationReplacementFormula, base.deprecationReplacementFormula),
            disabled: fields.contains(.disabled) ? disabled == true : base.disabled,
            disableDate: text(.disableDate, base.disableDate),
            disableReason: text(.disableReason, base.disableReason),
            disableReplacementCask: text(.disableReplacementCask, base.disableReplacementCask),
            disableReplacementFormula: text(.disableReplacementFormula, base.disableReplacementFormula)
        )
    }

    /// `brew upgrade` skips disabled casks but still upgrades deprecated ones.
    func target(inheriting cask: Cask) -> CaskUpdateTarget? {
        guard !(fields.contains(.disabled) ? disabled == true : cask.disabled),
              let version = fields.contains(.version) ? version : cask.version,
              !version.isEmpty
        else { return nil }
        return CaskUpdateTarget(
            version: version,
            autoUpdates: fields.contains(.autoUpdates) ? autoUpdates : cask.autoUpdates
        )
    }
}

nonisolated extension Cask {
    func updateTarget(for platform: CaskPlatform?) -> CaskUpdateTarget? {
        // A failed platform query cannot establish which version is compatible.
        guard provenance == .homebrewAPI, let tag = platform?.tag else { return nil }
        if let supportedPlatforms, !supportedPlatforms.contains(tag) { return nil }
        if let variation = variations?[tag] { return variation.target(inheriting: self) }
        // Homebrew uses the base fields when a known platform has no override.
        guard !disabled, !version.isEmpty else { return nil }
        return CaskUpdateTarget(version: version, autoUpdates: autoUpdates)
    }
}
