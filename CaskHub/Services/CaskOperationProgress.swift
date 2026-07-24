//
//  CaskOperationProgress.swift
//  CaskHub
//
//  Created by Ali Elsokary on 24/07/2026.
//

import Foundation

enum CaskOperationPhase: Equatable {
    case queued
    case preparing
    case downloading
    case verifying
    case performing
    case canceling

    func label(for action: CaskAction) -> String {
        switch self {
        case .queued:
            return "Queued"
        case .preparing:
            return "Preparing"
        case .downloading:
            return "Downloading"
        case .verifying:
            return "Verifying"
        case .performing:
            return action.inProgressLabel.replacingOccurrences(of: "…", with: "")
        case .canceling:
            return "Canceling"
        }
    }
}

struct CaskOperationProgress: Equatable {
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
        guard phase == .downloading, let byteProgressText else {
            return "\(phaseLabel)…"
        }
        return "\(phaseLabel) · \(byteProgressText)"
    }
}

struct CaskByteProgress: Equatable {
    let completedBytes: Int64
    let totalBytes: Int64

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }

    var text: String {
        let unit = ByteUnit.forTotalBytes(totalBytes)
        let clampedCompleted = min(max(completedBytes, 0), max(totalBytes, 0))
        return [
            Self.format(clampedCompleted, in: unit),
            "/",
            Self.format(totalBytes, in: unit),
            unit.symbol
        ].joined(separator: " ")
    }

    private static func format(_ bytes: Int64, in unit: ByteUnit) -> String {
        let formatted = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(bytes) / unit.divisor
        )
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
    }

    private enum ByteUnit {
        case bytes
        case kilobytes
        case megabytes
        case gigabytes

        static func forTotalBytes(_ bytes: Int64) -> ByteUnit {
            switch bytes {
            case 1_000_000_000...:
                return .gigabytes
            case 1_000_000...:
                return .megabytes
            case 1_000...:
                return .kilobytes
            default:
                return .bytes
            }
        }

        var divisor: Double {
            switch self {
            case .bytes: return 1
            case .kilobytes: return 1_000
            case .megabytes: return 1_000_000
            case .gigabytes: return 1_000_000_000
            }
        }

        var symbol: String {
            switch self {
            case .bytes: return "B"
            case .kilobytes: return "KB"
            case .megabytes: return "MB"
            case .gigabytes: return "GB"
            }
        }
    }
}

struct CaskUpdateAllProgress: Equatable {
    let currentIndex: Int
    let totalCount: Int
    let currentToken: String
    let currentDisplayName: String
}

struct CaskOperationStatus: Equatable {
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
                "Updating \(updateAll.currentIndex) of \(updateAll.totalCount)",
                updateAll.currentDisplayName
            ].joined(separator: " · ")
            let current = operations.first(where: { $0.token == updateAll.currentToken })
            let byteProgress = current?.phase == .downloading ? current?.byteProgress : nil
            return CaskOperationStatus(label: label, byteProgress: byteProgress)
        }

        let sortedOperations = operations.sorted {
            if $0.displayName == $1.displayName { return $0.token < $1.token }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        guard !sortedOperations.isEmpty else { return nil }

        if sortedOperations.count == 1, let operation = sortedOperations.first {
            let byteProgress = operation.phase == .downloading ? operation.byteProgress : nil
            var label = "\(operation.phase.label(for: operation.action)) \(operation.displayName)"
            if byteProgress == nil { label += "…" }
            return CaskOperationStatus(label: label, byteProgress: byteProgress)
        }

        var counts: [String: Int] = [:]
        for operation in sortedOperations {
            let label = operation.phase.label(for: operation.action).lowercased()
            counts[label, default: 0] += 1
        }
        let phaseOrder = [
            "downloading", "verifying", "installing", "updating", "adopting",
            "uninstalling", "repairing", "preparing", "canceling", "queued"
        ]
        let details = phaseOrder.compactMap { label -> String? in
            guard let count = counts[label], count > 0 else { return nil }
            return "\(count) \(label)"
        }
        let summary = "\(sortedOperations.count) operations in progress"
        return CaskOperationStatus(label: ([summary] + details).joined(separator: " · "))
    }
}

nonisolated enum BrewProgressParser {
    private static let progressPattern =
        #"Downloading\s+([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB)\s*/\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB)"#

    static func byteProgress(in output: String) -> (completed: Int64, total: Int64)? {
        guard let expression = try? NSRegularExpression(pattern: progressPattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = expression.matches(in: output, range: range).last,
              let completed = value(in: output, match: match, valueGroup: 1, unitGroup: 2),
              let total = value(in: output, match: match, valueGroup: 3, unitGroup: 4)
        else { return nil }
        return (completed, total)
    }

    static func latestPhase(in output: String) -> CaskOperationPhase? {
        let markers: [(String, CaskOperationPhase)] = [
            ("Downloading", .downloading),
            (" Verifying ", .verifying),
            ("Verifying checksum", .verifying),
            ("==> Installing Cask", .performing),
            ("==> Upgrading ", .performing)
        ]
        return markers.compactMap { marker, phase in
            output.range(of: marker, options: .backwards).map { ($0.lowerBound, phase) }
        }
        .max { $0.0 < $1.0 }?
        .1
    }

    private static func value(
        in output: String,
        match: NSTextCheckingResult,
        valueGroup: Int,
        unitGroup: Int
    ) -> Int64? {
        guard let valueRange = Range(match.range(at: valueGroup), in: output),
              let unitRange = Range(match.range(at: unitGroup), in: output),
              let value = Double(output[valueRange])
        else { return nil }
        let multiplier: Double = switch output[unitRange] {
        case "KB": 1_000
        case "MB": 1_000_000
        case "GB": 1_000_000_000
        default: 1
        }
        return Int64((value * multiplier).rounded())
    }
}
