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
        return String(trimmed.suffix(4_000))
    }

    /// Drops brew's \r progress frames so the error line stays classifiable.
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
