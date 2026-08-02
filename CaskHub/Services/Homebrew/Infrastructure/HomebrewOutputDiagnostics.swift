//
//  HomebrewOutputDiagnostics.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated enum HomebrewOutputDiagnostics {
    // BrewOutputCollector already caps its buffer at a 2000-char stripped tail;
    // the suffix here is the safety net for any other caller.
    static func make(from output: String) -> String {
        let trimmed = stripProgressNoise(from: output)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.suffix(4_000))
    }

    /// Brew rewrites download/extract progress with carriage returns; the raw
    /// frames bury the real error line and defeat failure-class matching.
    static func stripProgressNoise(from output: String) -> String {
        output.components(separatedBy: .newlines)
            .filter { !isProgressFrame($0) }
            .joined(separator: "\n")
    }

    private static func isProgressFrame(_ line: String) -> Bool {
        if line.unicodeScalars.contains(where: { (0x2800...0x28FF).contains($0.value) }) {
            return true
        }
        guard let range = line.range(of: "Downloading ") ?? line.range(of: "Extracting ")
            ?? line.range(of: "Verified ") else { return false }
        return line[range.upperBound...].contains("B/")
    }
}
