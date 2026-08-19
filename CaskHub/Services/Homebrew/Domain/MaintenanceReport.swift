//
//  MaintenanceReport.swift
//  CaskHub
//
//  Created by Ali Elsokary on 19/08/2026.
//

import Foundation

nonisolated struct HealthCheck: Equatable, Sendable, Identifiable {
    enum Status: Equatable, Sendable {
        case pass
        case advisory
    }

    let id: String
    let status: Status
    let label: String
    let detail: String
}

nonisolated enum BrewDoctorParser {
    /// Blocks start with `Warning:` or `Error:` and run until the next marker.
    static func warnings(from output: String) -> [HealthCheck] {
        var blocks: [[String]] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Warning: ") || line.hasPrefix("Error: ") {
                blocks.append([line])
            } else if !blocks.isEmpty {
                blocks[blocks.count - 1].append(line)
            }
        }
        return blocks.enumerated().map { index, lines in
            let message = lines[0]
                .replacingOccurrences(of: "Warning: ", with: "")
                .replacingOccurrences(of: "Error: ", with: "")
            let (label, firstLineRest) = splitLabel(from: message)
            let detailLines = ([firstLineRest] + lines.dropFirst())
                .filter { !$0.isEmpty }
            return HealthCheck(
                id: "doctor-\(index)",
                status: .advisory,
                label: label,
                detail: detailLines.joined(separator: "\n")
            )
        }
    }

    private static func splitLabel(from message: String) -> (label: String, rest: String) {
        guard let range = message.range(of: ". ") else {
            var label = message
            if label.hasSuffix(":") || label.hasSuffix(".") { label.removeLast() }
            return (label, "")
        }
        let label = String(message[..<range.lowerBound])
        let rest = String(message[range.upperBound...])
        return (label, rest)
    }
}

nonisolated enum MaintenanceVersion {
    /// `v6.0.18-29-ga2005e5` → `6.0.18`
    static func normalized(_ version: String) -> String {
        let base = version.split(separator: "-").first.map(String.init) ?? version
        return base.hasPrefix("v") ? String(base.dropFirst()) : base
    }

    static func isCurrent(local: String, latest: String) -> Bool? {
        guard let localParts = numericParts(of: local),
              let latestParts = numericParts(of: latest)
        else { return nil }
        for index in 0..<max(localParts.count, latestParts.count) {
            let localValue = index < localParts.count ? localParts[index] : 0
            let latestValue = index < latestParts.count ? latestParts[index] : 0
            if localValue != latestValue { return localValue > latestValue }
        }
        return true
    }

    private static func numericParts(of version: String) -> [Int]? {
        let parts = normalized(version).split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }
    }
}

nonisolated enum MaintenanceFormat {
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // The default nonnumeric formatting spells out "Zero KB".
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: value)
    }
}

nonisolated enum BrewCleanupParser {
    /// Sums superseded kegs from `brew cleanup --dry-run` lines like
    /// `Would remove: /opt/homebrew/Cellar/foo/1.0 (6,090 files, 28.2MB)`.
    static func supersededKegBytes(from output: String) -> Int64 {
        var total: Int64 = 0
        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("Would remove: "),
                  line.contains("/Cellar/") || line.contains("/Caskroom/")
            else { continue }
            total += lastSizeBytes(in: line) ?? 0
        }
        return total
    }

    static func lastSizeBytes(in line: String) -> Int64? {
        let pattern = #/([0-9][0-9.,]*)(B|KB|MB|GB|TB)\b/#
        guard let match = line.matches(of: pattern).last else { return nil }
        let digits = match.1.replacingOccurrences(of: ",", with: "")
        guard let value = Double(digits) else { return nil }
        let multiplier: Double
        switch match.2 {
        case "KB": multiplier = 1024
        case "MB": multiplier = 1024 * 1024
        case "GB": multiplier = 1024 * 1024 * 1024
        case "TB": multiplier = 1024 * 1024 * 1024 * 1024
        default: multiplier = 1
        }
        return Int64(value * multiplier)
    }
}

nonisolated enum BrewAutoremoveParser {
    /// `==> Would autoremove 3 unneeded formulae:` followed by one name per line.
    static func formulae(from output: String) -> [String] {
        var names: [String] = []
        var inList = false
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.contains("Would autoremove") {
                inList = true
                continue
            }
            guard inList else { continue }
            if line.isEmpty || line.hasPrefix("==>") { break }
            names.append(line)
        }
        return names
    }
}
