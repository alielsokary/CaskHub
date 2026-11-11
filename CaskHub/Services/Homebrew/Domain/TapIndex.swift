//
//  TapIndex.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Foundation

nonisolated struct TapSummary: Decodable, Hashable, Sendable {
    let name: String
    let remote: String?
    let official: Bool
    let trusted: Bool
    /// brew records trust for these taps under the remote URL, not `user/repo`.
    let customRemote: Bool
    let caskTokens: [String]
    let formulaNames: [String]
    let caskFiles: [String]
    let formulaFiles: [String]

    var caskCount: Int { caskTokens.count }
    var formulaCount: Int { formulaNames.count }

    init(
        name: String, remote: String?, official: Bool, trusted: Bool, customRemote: Bool,
        caskTokens: [String], formulaNames: [String], caskFiles: [String], formulaFiles: [String]
    ) {
        self.name = name
        self.remote = remote
        self.official = official
        self.trusted = trusted
        self.customRemote = customRemote
        self.caskTokens = caskTokens
        self.formulaNames = formulaNames
        self.caskFiles = caskFiles
        self.formulaFiles = formulaFiles
    }

    /// API-backed official taps omit file lists and remotes; one such entry must not sink the whole list.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        remote = try container.decodeIfPresent(String.self, forKey: .remote)
        official = try container.decodeIfPresent(Bool.self, forKey: .official) ?? false
        trusted = try container.decodeIfPresent(Bool.self, forKey: .trusted) ?? false
        customRemote = try container.decodeIfPresent(Bool.self, forKey: .customRemote) ?? false
        caskTokens = try container.decodeIfPresent([String].self, forKey: .caskTokens) ?? []
        formulaNames = try container.decodeIfPresent([String].self, forKey: .formulaNames) ?? []
        caskFiles = try container.decodeIfPresent([String].self, forKey: .caskFiles) ?? []
        formulaFiles = try container.decodeIfPresent([String].self, forKey: .formulaFiles) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case name, remote, official, trusted, customRemote, caskTokens, formulaNames, caskFiles, formulaFiles
    }
}

nonisolated struct TapTrust: Decodable, Equatable, Sendable {
    let taps: Set<String>
    let casks: Set<String>

    func trusts(_ reference: String) -> Bool {
        guard let tap = CaskReference.tap(of: reference) else { return true }
        return casks.contains(reference) || taps.contains(tap)
    }
}

/// A tap formula, shown but not managed: CaskHub only installs casks.
nonisolated struct TapFormula: Hashable, Sendable, Identifiable {
    let name: String
    let tap: String
    let desc: String?
    let homepage: String
    let version: String

    var reference: String { "\(tap)/\(name)" }
    var id: String { reference }
    var installCommand: String { "brew install \(reference)" }
    var searchKey: String { "\(name)\n\(desc ?? "")".lowercased() }
}

/// Every third-party tap on the Mac and its casks, published only as a whole.
nonisolated struct TapIndex: Equatable, Sendable {
    let taps: [TapSummary]
    let casks: [Cask]
    let trust: TapTrust
    let formulae: [TapFormula]

    static let empty = TapIndex(taps: [], casks: [], trust: TapTrust(taps: [], casks: []), formulae: [])

    func trusts(_ reference: String) -> Bool {
        guard let tapName = CaskReference.tap(of: reference) else { return true }
        if trust.trusts(reference) { return true }
        guard let tap = taps.first(where: { $0.name == tapName }) else { return false }
        if tap.trusted { return true }
        guard tap.customRemote, let remote = tap.remote?.lowercased() else { return false }
        return trust.taps.contains(remote) || trust.casks.contains("\(remote)/\(CaskReference.bareToken(reference))")
    }

    func casks(in tap: String) -> [Cask] {
        casks.filter { $0.tap == tap }
    }
}
