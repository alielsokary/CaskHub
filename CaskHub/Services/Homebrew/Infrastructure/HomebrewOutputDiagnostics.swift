//
//  HomebrewOutputDiagnostics.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated enum HomebrewOutputDiagnostics {
    static func make(from output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
