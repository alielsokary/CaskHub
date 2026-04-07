//
//  CaskIconURL.swift
//  CaskHub
//
//  Created by Ali Elsokary on 27/03/2026.
//

import Foundation

enum CaskIconURL {
    /// High-quality app icon from App-Fair/appcasks GitHub releases (~74% coverage of pre-2022 casks)
    static func appIconURL(for token: String) -> URL? {
        URL(string: "https://github.com/App-Fair/appcasks/releases/download/cask-\(token)/AppIcon.png")
    }

    /// GitHub owner extracted from homepage or download URL — caller should verify it's an org before using the avatar
    static func gitHubOwner(homepage: String, downloadURL: String?) -> String? {
        if let owner = extractGitHubOwner(from: homepage) {
            return owner
        }
        if let downloadURL, let owner = extractGitHubOwner(from: downloadURL) {
            return owner
        }
        return nil
    }

    /// GitHub owner avatar — only meaningful for organizations (personal accounts return developer faces)
    static func gitHubAvatarURL(for owner: String) -> URL? {
        URL(string: "https://github.com/\(owner).png?size=128")
    }

    /// High-quality favicon via icon.horse (returns 404 on missing favicon, unlike Google's generic globe)
    static func faviconURL(for homepage: String) -> URL? {
        guard let host = URL(string: homepage)?.host else { return nil }
        // Skip shared platform domains — their favicons are generic
        let sharedDomains: Set<String> = [
            "github.com", "sourceforge.net", "aka.ms",
            "bitbucket.org", "gitlab.com", "codeberg.org"
        ]
        guard !sharedDomains.contains(host) else { return nil }
        return URL(string: "https://icon.horse/icon/\(host)")
    }

    // MARK: - Private

    /// Extracts the GitHub owner from URLs like "https://github.com/{owner}/..."
    private static func extractGitHubOwner(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              url.host == "github.com" || url.host == "www.github.com" else {
            return nil
        }
        let pathComponents = url.pathComponents
        // pathComponents[0] is "/", [1] is the owner
        guard pathComponents.count >= 2 else { return nil }
        let owner = pathComponents[1]
        guard !owner.isEmpty, owner != "downloads" else { return nil }
        return owner
    }
}
