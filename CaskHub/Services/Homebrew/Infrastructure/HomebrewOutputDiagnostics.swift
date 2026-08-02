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
        let limit = 8_192
        guard trimmed.count > limit else { return trimmed }

        let important = trimmed.components(separatedBy: .newlines).filter { line in
            let lowercase = line.lowercased()
            return line.contains("Error:")
                || line.contains("Warning:")
                || lowercase.contains("failed")
                || line.contains("Operation not permitted")
        }
        let importantText = String(
            important.joined(separator: "\n").prefix(2_000)
        )
        let tail = String(trimmed.suffix(limit - 2_100))
        return importantText.isEmpty
            ? String(trimmed.suffix(limit))
            : importantText + "\n…\n" + tail
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
