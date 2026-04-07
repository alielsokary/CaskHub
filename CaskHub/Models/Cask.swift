//
//  Cask.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/02/2026.
//

import Foundation

struct Cask: Codable, Identifiable, Hashable {
    let token: String
    let name: [String]
    let desc: String?
    let homepage: String
    let url: String?
    let version: String
    let installed: String?
    let outdated: Bool
    let deprecated: Bool
    let disabled: Bool
    let autoUpdates: Bool?

    var id: String { token }

    var displayName: String {
        name.first ?? token
    }

    var displayVersion: String {
        let base = version.split(separator: ",", maxSplits: 1).first.map(String.init) ?? version

        let numeric = String(base.prefix(while: { $0.isNumber || $0 == "." }))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return numeric.isEmpty ? base : numeric
    }

    var homepageDomain: String? {
        URL(string: homepage)?.host
    }
}
