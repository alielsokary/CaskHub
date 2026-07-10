//
//  CaskIconURL.swift
//  CaskHub
//
//  Created by Ali Elsokary on 27/03/2026.
//

import Foundation

/// Icon sources, all original app icons keyed by cask token — no generated
/// fallbacks (favicons, avatars). Casks without an extracted icon show the
/// placeholder until CaskFlow's daily pipeline picks them up.
enum CaskIconURL {
    /// Original app icons extracted by CaskFlow (icons branch, keyed by token).
    /// jsDelivr edge CDN first, raw.githubusercontent.com as fallback.
    static func caskFlowIconURLs(for token: String) -> [URL] {
        [
            URL(string: "https://cdn.jsdelivr.net/gh/alielsokary/CaskFlow@icons/\(token).png"),
            URL(string: "https://raw.githubusercontent.com/alielsokary/CaskFlow/icons/\(token).png")
        ].compactMap { $0 }
    }

    /// App-Fair/appcasks GitHub releases — also original icons, but frozen
    /// pre-2022. Covers some casks CaskFlow can't extract (EULA walls, dead
    /// vendor URLs that worked back then).
    static func appFairIconURL(for token: String) -> URL? {
        URL(string: "https://github.com/App-Fair/appcasks/releases/download/cask-\(token)/AppIcon.png")
    }
}
