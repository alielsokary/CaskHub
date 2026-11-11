//
//  CaskFileTextParser.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Foundation

/// Reads display fields from an untrusted tap cask file as plain text; tap Ruby is never evaluated.
nonisolated enum CaskFileTextParser {
    private static let maxSourceBytes = 64 * 1024

    static func cask(fromSource source: String, token: String, tap: String) -> Cask {
        let text = String(decoding: source.utf8.prefix(maxSourceBytes), as: UTF8.self)
        return Cask.tapSourceRow(
            token: token,
            tap: tap,
            name: firstLiteral("name", in: text),
            desc: firstLiteral("desc", in: text),
            homepage: firstLiteral("homepage", in: text) ?? "",
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
