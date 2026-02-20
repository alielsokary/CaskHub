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

    var homepageDomain: String? {
        URL(string: homepage)?.host
    }
}
