//
//  CaskFileTextParser.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Foundation

/// Reads display fields from an untrusted tap cask file as plain text; tap Ruby is never evaluated.
nonisolated enum CaskFileTextParser {
    private static let maxSourceCharacters = 64 * 1024

    static func cask(fromSource source: String, token: String, tap: String) -> Cask {
        let text = String(source.prefix(maxSourceCharacters))
        var cask = Cask(
            token: token, fullToken: "\(tap)/\(token)", tap: tap,
            name: [firstLiteral("name", in: text) ?? token],
            desc: firstLiteral("desc", in: text),
            homepage: firstLiteral("homepage", in: text).flatMap(URL.web)?.absoluteString ?? "",
            url: nil, sha256: nil,
            version: version(in: text) ?? "",
            bundleVersion: nil, bundleShortVersion: nil,
            outdated: false, deprecated: false, disabled: false,
            autoUpdates: nil, variations: nil, supportedPlatforms: nil, conflictsWith: nil,
            deprecationDate: nil, deprecationReason: nil,
            deprecationReplacementCask: nil, deprecationReplacementFormula: nil,
            disableDate: nil, disableReason: nil,
            disableReplacementCask: nil, disableReplacementFormula: nil
        )
        cask.provenance = .tapSource
        return cask
    }

    static func formula(fromSource source: String, name: String, tap: String) -> TapFormula {
        let text = String(source.prefix(maxSourceCharacters))
        return TapFormula(
            name: name,
            tap: tap,
            desc: firstLiteral("desc", in: text),
            homepage: firstLiteral("homepage", in: text).flatMap(URL.web)?.absoluteString ?? "",
            version: version(in: text) ?? ""
        )
    }

    private static func version(in text: String) -> String? {
        let literal = firstMatch(#"^[ \t]*version[ \t]+"([^"\n]*)""#, in: text)
        let latest = firstMatch(#"^[ \t]*version[ \t]+:(latest)\b"#, in: text)
        switch (literal, latest) {
        case let (literal?, latest?): return literal.offset < latest.offset ? usable(literal.value) : "latest"
        case let (literal?, nil): return usable(literal.value)
        case (nil, .some): return "latest"
        case (nil, nil): return nil
        }
    }

    private static func firstLiteral(_ stanza: String, in text: String) -> String? {
        firstMatch(#"^[ \t]*\#(stanza)[ \t]+"([^"\n]*)""#, in: text).flatMap { usable($0.value) }
    }

    private static func usable(_ value: String) -> String? {
        value.isEmpty || value.contains("#{") ? nil : value
    }

    private static func firstMatch(_ pattern: String, in text: String) -> (value: String, offset: Int)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return (String(text[range]), match.range.location)
    }
}

extension URL {
    /// Tap-authored strings become clickable only as http(s) links with a host.
    nonisolated static func web(_ text: String) -> URL? {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else { return nil }
        return url
    }
}
