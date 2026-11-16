//
//  CaskIconURL.swift
//  CaskHub
//
//  Created by Ali Elsokary on 27/03/2026.
//

import Foundation

enum CaskIconURL {
    /// Official tokens sit at the branch root; tap references (`user/repo/token`) under `taps/`.
    static func caskFlowIconURLs(for reference: String) -> [URL] {
        let path = reference.contains("/") ? "taps/\(reference)" : reference
        return [
            URL(string: "https://cdn.jsdelivr.net/gh/alielsokary/CaskFlow@icons/\(path).png"),
            URL(string: "https://raw.githubusercontent.com/alielsokary/CaskFlow/icons/\(path).png")
        ].compactMap { $0 }
    }

    static func appFairIconURL(for token: String) -> URL? {
        URL(string: "https://github.com/App-Fair/appcasks/releases/download/cask-\(token)/AppIcon.png")
    }
}
