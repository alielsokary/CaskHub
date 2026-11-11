//
//  TrustInstallPrompt.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Foundation

/// Consent copy shown before a tap cask's first install, which makes brew trust it.
nonisolated struct TrustInstallPrompt: Equatable {
    let cask: Cask

    private var source: String {
        cask.thirdPartyTap ?? cask.tap ?? ""
    }

    var title: String {
        String(localized: "Install \(cask.displayName) from \(source)?")
    }

    var message: String {
        Self.message(name: cask.displayName, tap: source)
    }

    static func message(name: String, tap: String) -> String {
        String(localized: "\(name) comes from \(tap), not Homebrew. Installing lets it run code on this Mac.")
    }
}
