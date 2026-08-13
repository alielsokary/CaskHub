//
//  HomebrewOutputDiagnostics.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated enum HomebrewOutputDiagnostics {
    static func make(from output: String) -> String {
        let trimmed = stripProgressNoise(from: output)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Sentry caps long messages from the head; keep the root-cause lines
        // that print just above brew's final Error: wrapper.
        if trimmed.count > 1_200,
           let range = trimmed.range(of: "\nError:", options: .backwards),
           let contextStart = trimmed.index(
               range.lowerBound, offsetBy: -600, limitedBy: trimmed.startIndex
           ) {
            let sliced = trimmed[contextStart...].drop { $0 != "\n" }.dropFirst()
            return String(sliced.suffix(4_000))
        }
        return String(trimmed.suffix(4_000))
    }

    /// Matched per line — the collector strips per pty chunk, so a block
    /// trigger can arrive in a different chunk than its body.
    private static let tapTrustNoiseMarkers = [
        "taps are not trusted",
        "tap trust is required",
        "Prefer trusting only",
        "these taps with:",
        "To trust these taps",
        "brew trust ",
        "Whole-tap trust",
        "Trust whole taps",
        "Untap them with:",
        "brew untap ",
        "To disable trust checks",
        "HOMEBREW_NO_REQUIRE_TAP_TRUST",
        "not recommended and will be removed",
        "For more information, see:",
        "docs.brew.sh/Tap-Trust"
    ]

    /// Drops brew's \r progress frames and the multi-KB tap-trust advisory so
    /// the error line stays classifiable.
    static func stripProgressNoise(from output: String) -> String {
        output.components(separatedBy: .newlines)
            .filter { line in
                if !line.hasPrefix("Error:"),
                   tapTrustNoiseMarkers.contains(where: line.contains) { return false }
                // brew's --force overwrite warning reuses the conflict-error sentence.
                if line.contains("; overwriting.") { return false }
                return !isProgressFrame(line)
            }
            .joined(separator: "\n")
    }

    private static func isProgressFrame(_ line: String) -> Bool {
        if line.unicodeScalars.contains(where: { (0x2800...0x28FF).contains($0.value) }) {
            return true
        }
        guard let range = line.range(of: "Downloading ") ?? line.range(of: "Downloaded ")
            ?? line.range(of: "Extracting ") ?? line.range(of: "Verified ") else { return false }
        return line[range.upperBound...].contains("B/")
    }
}
