//
//  RecentlyAddedTracker.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/04/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class RecentlyAddedTracker {
    private var firstSeenDates: [String: Date] = [:]
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "CaskHub", isDirectory: true)
        fileURL = appDir.appendingPathComponent("recently_added.json")
        load()
    }

    /// Call after every successful cask fetch.
    /// First run records all tokens with `.distantPast` as a silent baseline.
    /// Subsequent runs mark genuinely new tokens with the current date.
    func updateWithCurrentTokens(_ tokens: Set<String>) {
        let isFirstRun = firstSeenDates.isEmpty
        let knownTokens = Set(firstSeenDates.keys)
        let newTokens = tokens.subtracting(knownTokens)

        guard !newTokens.isEmpty else { return }

        let timestamp = isFirstRun ? Date.distantPast : Date.now
        for token in newTokens {
            firstSeenDates[token] = timestamp
        }
        save()
    }

    /// Returns tokens first seen within the given window (default: 14 days).
    func recentTokens(within days: Int = 14) -> Set<String> {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return Set(firstSeenDates.filter { $0.value >= cutoff }.keys)
    }

    /// Returns the date a token was first seen, or `nil` if unknown.
    func firstSeenDate(for token: String) -> Date? {
        firstSeenDates[token]
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        firstSeenDates = (try? decoder.decode([String: Date].self, from: data)) ?? [:]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(firstSeenDates) else { return }

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
