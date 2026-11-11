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
    let caskTokens: [String]
    let formulaNames: [String]
    let caskFiles: [String]

    var caskCount: Int { caskTokens.count }
    var formulaCount: Int { formulaNames.count }
}

nonisolated struct TapTrust: Decodable, Equatable, Sendable {
    let taps: Set<String>
    let casks: Set<String>

    func trusts(_ reference: String) -> Bool {
        guard let tap = CaskReference.tap(of: reference) else { return true }
        return casks.contains(reference) || taps.contains(tap)
    }
}

/// Every third-party tap on the Mac and its casks, published only as a whole.
nonisolated struct TapIndex: Equatable, Sendable {
    let taps: [TapSummary]
    let casks: [Cask]
    let trust: TapTrust

    static let empty = TapIndex(taps: [], casks: [], trust: TapTrust(taps: [], casks: []))

    func casks(in tap: String) -> [Cask] {
        casks.filter { $0.tap == tap }
    }
}
