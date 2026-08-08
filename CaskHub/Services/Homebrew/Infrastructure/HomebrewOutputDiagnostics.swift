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
        // Sentry keeps the head of long messages while we keep the tail — slice
        // long payloads to the last Error: line so preambles can't push it past
        // Sentry's cap.
        if trimmed.count > 1_200,
           let range = trimmed.range(of: "\nError:", options: .backwards) {
            return String(trimmed[trimmed.index(after: range.lowerBound)...].suffix(4_000))
        }
        return String(trimmed.suffix(4_000))
    }

    /// Drops brew's \r progress frames and the multi-KB tap-trust advisory so
    /// the error line stays classifiable.
    static func stripProgressNoise(from output: String) -> String {
        var insideTapTrustAdvisory = false
        return output.components(separatedBy: .newlines)
            .filter { line in
                if line.contains("The following taps are not trusted") {
                    insideTapTrustAdvisory = true
                }
                if insideTapTrustAdvisory {
                    if line.contains("docs.brew.sh/Tap-Trust") {
                        insideTapTrustAdvisory = false
                        return false
                    }
                    // Escape hatch: a truncated advisory must not swallow the error.
                    if line.hasPrefix("Error:") || line.hasPrefix("==>") {
                        insideTapTrustAdvisory = false
                    } else {
                        return false
                    }
                }
                // --force overwrite warnings reuse the conflict-error sentence;
                // keeping them misclassifies unrelated --force failures.
                if line.contains("; overwriting.") { return false }
                return !isProgressFrame(line)
            }
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
