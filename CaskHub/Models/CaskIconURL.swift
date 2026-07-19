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

    static func appFairIconURL(for token: String) -> URL? {
        URL(string: "https://github.com/App-Fair/appcasks/releases/download/cask-\(token)/AppIcon.png")
    }
}
