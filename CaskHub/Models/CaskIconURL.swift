//
//  CaskIconURL.swift
//  CaskHub
//
//  Created by Ali Elsokary on 27/03/2026.
//

import Foundation

enum CaskIconURL {
    static func caskFlowIconURLs(for token: String) -> [URL] {
        [
            URL(string: "https://cdn.jsdelivr.net/gh/alielsokary/CaskFlow@icons/\(token).png"),
            URL(string: "https://raw.githubusercontent.com/alielsokary/CaskFlow/icons/\(token).png")
        ].compactMap { $0 }
    }

    static func tapIconURLs(for cask: Cask) -> [URL] {
        guard let tap = cask.thirdPartyTap else { return [] }
        let parts = tap.split(separator: "/")
        guard parts.count == 2 else { return [] }
        let base = "https://raw.githubusercontent.com/\(parts[0])/homebrew-\(parts[1])/HEAD"
        return ["Icons", "icons"].compactMap {
            URL(string: "\(base)/\($0)/\(cask.token).png")
        }
    }

    static func appFairIconURL(for token: String) -> URL? {
        URL(string: "https://github.com/App-Fair/appcasks/releases/download/cask-\(token)/AppIcon.png")
    }
}
