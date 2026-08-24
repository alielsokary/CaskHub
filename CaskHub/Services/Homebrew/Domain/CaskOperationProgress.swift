//
//  CaskOperationProgress.swift
//  CaskHub
//
//  Created by Ali Elsokary on 24/07/2026.
//

import Foundation

nonisolated enum CaskOperationPhase: Equatable, Sendable {
    case queued
    case preparing
    case checkingDownload
    case downloading
    case usingCachedDownload
    case verifying
    case performing
    case canceling

    func label(for action: CaskAction) -> String {
        switch self {
        case .queued:
            return String(localized: "Queued")
        case .preparing:
            return String(localized: "Preparing")
        case .checkingDownload:
            return String(localized: "Checking download")
        case .downloading:
            return String(localized: "Downloading")
        case .usingCachedDownload:
            return String(localized: "Using cache")
        case .verifying:
            return String(localized: "Verifying")
        case .performing:
            return action.inProgressLabel.replacingOccurrences(of: "…", with: "")
        case .canceling:
            return String(localized: "Canceling")
        }
    }

    /// Stable key for grouping and ordering. Never shown to the user, so it stays
    /// fixed when `label(for:)` changes wording.
    func identifier(for action: CaskAction) -> String {
        switch self {
        case .queued:
            return "queued"
        case .preparing:
            return "preparing"
        case .checkingDownload:
            return "checking-download"
        case .downloading:
            return "downloading"
        case .usingCachedDownload:
            return "using-cache"
        case .verifying:
            return "verifying"
        case .performing:
            return action.identifier
        case .canceling:
            return "canceling"
        }
    }

    var isDownloadActivity: Bool {
        switch self {
        case .checkingDownload, .downloading, .usingCachedDownload:
            return true
        default:
            return false
        }
    }

    var showsByteProgress: Bool {
        self == .downloading || self == .usingCachedDownload
    }
}

nonisolated struct CaskOperationProgress: Equatable, Sendable {
    let token: String
    let displayName: String
    let action: CaskAction
    var phase: CaskOperationPhase
    var completedBytes: Int64?
    var totalBytes: Int64?

    var fractionCompleted: Double? {
        byteProgress?.fractionCompleted
    }

    var byteProgress: CaskByteProgress? {
        guard let completedBytes, let totalBytes, totalBytes > 0 else { return nil }
        return CaskByteProgress(completedBytes: completedBytes, totalBytes: totalBytes)
    }

    var byteProgressText: String? {
        byteProgress?.text
    }

    var inlineLabel: String {
        let phaseLabel = phase.label(for: action)
        guard phase.showsByteProgress, let byteProgressText else {
            return "\(phaseLabel)…"
        }
        return "\(phaseLabel) · \(byteProgressText)"
    }
}

nonisolated struct CaskByteProgress: Equatable, Sendable {
    let completedBytes: Int64
    let totalBytes: Int64

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }

    var text: String {
        let unit = Self.units.first { totalBytes >= $0.threshold } ?? Self.units[3]
        let clampedCompleted = min(max(completedBytes, 0), max(totalBytes, 0))
        let completedText = Self.format(clampedCompleted, divisor: unit.divisor)
        let totalText = Self.format(totalBytes, divisor: unit.divisor)
        return "\(completedText) / \(totalText) \(unit.symbol)"
    }

    private struct Unit {
        let threshold: Int64
        let divisor: Double
        let symbol: String
    }

    private static let units: [Unit] = [
        Unit(threshold: 1_000_000_000, divisor: 1e9, symbol: "GB"),
        Unit(threshold: 1_000_000, divisor: 1e6, symbol: "MB"),
        Unit(threshold: 1_000, divisor: 1e3, symbol: "KB"),
        Unit(threshold: 0, divisor: 1, symbol: "B")
    ]

    private static func format(_ bytes: Int64, divisor: Double) -> String {
        let formatted = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(bytes) / divisor
        )
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
    }
}

nonisolated struct CaskUpdateAllProgress: Equatable, Sendable {
    let currentIndex: Int
    let totalCount: Int
    let currentToken: String
    let currentDisplayName: String
}

nonisolated struct CaskOperationStatus: Equatable, Sendable {
    let label: String
    let byteProgress: CaskByteProgress?

    init(label: String, byteProgress: CaskByteProgress? = nil) {
        self.label = label
        self.byteProgress = byteProgress
    }

    var message: String {
        guard let byteProgress else { return label }
        return "\(label) · \(byteProgress.text)"
    }

    static func make(
        operations: [CaskOperationProgress],
        updateAll: CaskUpdateAllProgress?
    ) -> CaskOperationStatus? {
        if let updateAll {
            let label = [
                String(localized: "Updating \(updateAll.currentIndex) of \(updateAll.totalCount)"),
                updateAll.currentDisplayName
            ].joined(separator: " · ")
            let current = operations.first(where: { $0.token == updateAll.currentToken })
            let byteProgress = current?.phase.showsByteProgress == true
                ? current?.byteProgress
                : nil
            return CaskOperationStatus(label: label, byteProgress: byteProgress)
        }

        let sortedOperations = operations.sorted {
            if $0.displayName == $1.displayName { return $0.token < $1.token }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        guard !sortedOperations.isEmpty else { return nil }

        if sortedOperations.count == 1, let operation = sortedOperations.first {
            let byteProgress = operation.phase.showsByteProgress ? operation.byteProgress : nil
            var label = "\(operation.phase.label(for: operation.action)) \(operation.displayName)"
            if byteProgress == nil { label += "…" }
            return CaskOperationStatus(label: label, byteProgress: byteProgress)
        }

        var counts: [String: (count: Int, label: String)] = [:]
        for operation in sortedOperations {
            let identifier = operation.phase.identifier(for: operation.action)
            let label = operation.phase.label(for: operation.action).lowercased()
            counts[identifier, default: (count: 0, label: label)].count += 1
        }
        let phaseOrder = [
            "downloading", "checking-download", "using-cache", "verifying", "installing",
            "updating", "updating-homebrew", "adopting", "uninstalling", "repairing", "preparing",
            "canceling", "queued"
        ]
        let details = phaseOrder.compactMap { identifier -> String? in
            guard let entry = counts[identifier], entry.count > 0 else { return nil }
            return "\(entry.count) \(entry.label)"
        }
        let summary = String(localized: "\(sortedOperations.count) operations in progress")
        return CaskOperationStatus(label: ([summary] + details).joined(separator: " · "))
    }
}

nonisolated enum BrewProgressParser {
    struct Update {
        let phase: CaskOperationPhase?
        let byteProgress: (completed: Int64, total: Int64)?
        let cachedDownloadPath: String?
    }

    private static let progressRegex =
        #/Downloading\s+([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB)\s*\/\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB)/#

    static func parse(_ output: String) -> Update {
        let progressMatch = output.matches(of: progressRegex).last
        let byteProgress: (completed: Int64, total: Int64)? = progressMatch.flatMap { match in
            guard let completed = bytes(match.1, unit: match.2),
                  let total = bytes(match.3, unit: match.4)
            else { return nil }
            return (completed, total)
        }

        var events: [(String.Index, CaskOperationPhase)] = []
        if let progressMatch {
            events.append((progressMatch.range.lowerBound, .downloading))
        }

        let markers: [(String, CaskOperationPhase)] = [
            ("==> Downloading ", .checkingDownload),
            ("Already downloaded:", .usingCachedDownload),
            (" Verifying ", .verifying),
            ("Verifying checksum", .verifying),
            ("==> Installing Cask", .performing),
            ("==> Upgrading ", .performing)
        ]
        events += markers.compactMap { marker, phase in
            output.range(of: marker, options: .backwards).map {
                ($0.lowerBound, phase)
            }
        }

        let phase = events.max { $0.0 < $1.0 }?.1
        let cachedPath: String?
        switch phase {
        case .usingCachedDownload:
            cachedPath = cachedDownloadPath(in: output)
        default:
            cachedPath = nil
        }

        return Update(
            phase: phase,
            byteProgress: byteProgress,
            cachedDownloadPath: cachedPath
        )
    }

    private static func bytes(_ value: Substring, unit: Substring) -> Int64? {
        guard let value = Double(value) else { return nil }
        let multiplier: Double = switch unit {
        case "KB": 1_000
        case "MB": 1_000_000
        case "GB": 1_000_000_000
        default: 1
        }
        return Int64((value * multiplier).rounded())
    }

    private static func cachedDownloadPath(in output: String) -> String? {
        let prefix = "Already downloaded:"
        guard let line = output.components(separatedBy: .newlines).reversed().first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }) else { return nil }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let path = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return path.hasPrefix("/") ? path : nil
    }
}
