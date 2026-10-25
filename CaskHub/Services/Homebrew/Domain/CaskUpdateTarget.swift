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
    private let deprecationDate: String?
    private let deprecationReason: String?
    private let deprecationReplacementCask: String?
    private let deprecationReplacementFormula: String?
    private let disableDate: String?
    private let disableReason: String?
    private let disableReplacementCask: String?
    private let disableReplacementFormula: String?
    private let fields: Set<CodingKeys>

    private enum CodingKeys: String, CodingKey {
        case version, autoUpdates, disabled, deprecated
        case deprecationDate, deprecationReason, deprecationReplacementCask, deprecationReplacementFormula
        case disableDate, disableReason, disableReplacementCask, disableReplacementFormula
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fields = Set(values.allKeys)
        version = try values.decodeIfPresent(String.self, forKey: .version)
        autoUpdates = try values.decodeIfPresent(Bool.self, forKey: .autoUpdates)
        disabled = try values.decodeIfPresent(Bool.self, forKey: .disabled)
        deprecated = try values.decodeIfPresent(Bool.self, forKey: .deprecated)
        deprecationDate = try values.decodeIfPresent(String.self, forKey: .deprecationDate)
        deprecationReason = try values.decodeIfPresent(String.self, forKey: .deprecationReason)
        deprecationReplacementCask = try values.decodeIfPresent(String.self, forKey: .deprecationReplacementCask)
        deprecationReplacementFormula = try values.decodeIfPresent(String.self, forKey: .deprecationReplacementFormula)
        disableDate = try values.decodeIfPresent(String.self, forKey: .disableDate)
        disableReason = try values.decodeIfPresent(String.self, forKey: .disableReason)
        disableReplacementCask = try values.decodeIfPresent(String.self, forKey: .disableReplacementCask)
        disableReplacementFormula = try values.decodeIfPresent(String.self, forKey: .disableReplacementFormula)
    }

    func retirementFields(inheriting base: CaskRetirementFields) -> CaskRetirementFields {
        func pick<Value>(_ key: CodingKeys, _ value: Value, _ inherited: Value) -> Value {
            fields.contains(key) ? value : inherited
        }
        return CaskRetirementFields(
            deprecated: fields.contains(.deprecated) ? deprecated == true : base.deprecated,
            deprecationDate: pick(.deprecationDate, deprecationDate, base.deprecationDate),
            deprecationReason: pick(.deprecationReason, deprecationReason, base.deprecationReason),
            deprecationReplacementCask: pick(
                .deprecationReplacementCask, deprecationReplacementCask, base.deprecationReplacementCask
            ),
            deprecationReplacementFormula: pick(
                .deprecationReplacementFormula, deprecationReplacementFormula, base.deprecationReplacementFormula
            ),
            disabled: fields.contains(.disabled) ? disabled == true : base.disabled,
            disableDate: pick(.disableDate, disableDate, base.disableDate),
            disableReason: pick(.disableReason, disableReason, base.disableReason),
            disableReplacementCask: pick(.disableReplacementCask, disableReplacementCask, base.disableReplacementCask),
            disableReplacementFormula: pick(
                .disableReplacementFormula, disableReplacementFormula, base.disableReplacementFormula
            )
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

extension Cask {
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
