//
//  CaskReference.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Foundation

/// A cask's identity: the bare token for official casks, `user/repo/token` for tap casks.
nonisolated enum CaskReference {
    static let thirdPartyName = "third-party"

    static func isOfficial(tap: String?) -> Bool {
        guard let tap else { return true }
        // Every `Cask.reference` read lands here; the API's lowercase taps skip the allocating lowercased().
        return tap.hasPrefix("homebrew/") || tap.lowercased().hasPrefix("homebrew/")
    }

    static func make(token: String, tap: String?) -> String {
        guard let tap, !isOfficial(tap: tap) else { return token }
        return "\(tap)/\(token)"
    }

    /// Called several times per cask on every library rebuild, so official tokens return without allocating.
    static func bareToken(_ reference: String) -> String {
        guard let slash = reference.utf8.lastIndex(of: UInt8(ascii: "/")) else { return reference }
        return String(reference[reference.utf8.index(after: slash)...])
    }

    static func tap(of reference: String) -> String? {
        let parts = reference.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let tap = "\(parts[0])/\(parts[1])"
        return isOfficial(tap: tap) ? nil : tap
    }

    static func normalized(_ brewfileToken: String) -> String {
        let parts = brewfileToken.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return brewfileToken }
        return make(token: String(parts[2]), tap: "\(parts[0])/\(parts[1])")
    }

    static func analyticsName(_ reference: String) -> String {
        reference.contains("/") ? thirdPartyName : reference
    }
}

nonisolated extension Cask {
    var thirdPartyTap: String? {
        CaskReference.tap(of: reference)
    }
}

nonisolated extension InstallationSnapshot {
    func installation(for reference: String) -> LocalCaskInstallation? {
        guard let installation = installedCasks[CaskReference.bareToken(reference)],
              CaskReference.make(token: installation.token, tap: installation.tap) == reference
        else { return nil }
        return installation
    }

    /// Who owns the Caskroom entry when a same-token twin, not this cask, is installed.
    func foreignInstallationSource(for reference: String) -> String? {
        guard let installation = installedCasks[CaskReference.bareToken(reference)],
              CaskReference.make(token: installation.token, tap: installation.tap) != reference
        else { return nil }
        return CaskReference.isOfficial(tap: installation.tap) ? "Homebrew" : installation.tap
    }
}
