//
//  TrustInstallPrompt.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Foundation

/// Consent copy shown before a tap cask's first install, which makes brew trust it.
/// Built only from the token and tap name: the cask's own `name` is tap-authored text.
nonisolated struct TrustInstallPrompt: Equatable {
    let cask: Cask

    private var source: String {
        Self.safeLabel(cask.thirdPartyTap ?? cask.tap ?? "")
    }

    private var token: String {
        Self.safeLabel(cask.token)
    }

    static func safeLabel(_ text: String) -> String {
        String(text.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "._@+-/".contains($0)) }.prefix(80))
    }

    var title: String {
        String(localized: "Trust and install \(token) from \(source)?")
    }

    var message: String {
        Self.message(name: token, tap: source)
    }

    static func message(name: String, tap: String) -> String {
        String(localized: """
            \(name) comes from \(tap), not Homebrew. \
            Installing makes Homebrew trust this cask and lets it run code on this Mac.
            """)
    }
}
