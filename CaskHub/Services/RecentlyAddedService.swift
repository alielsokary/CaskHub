//
//  RecentlyAddedService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/07/2026.
//

import Foundation
import Observation

/// Window options for the Recently Added page.
enum RecentlyAddedWindow: Int, CaseIterable, Identifiable {
    case days30 = 30
    case days60 = 60
    case days90 = 90

    var id: Int {
        rawValue
    }

    var label: String {
        "\(rawValue) Days"
    }
}

/// Cask token → date it was added to homebrew-cask, mined from the tap's git
/// history by CaskFlow and published as `added_dates.json` with each data
/// release. Dates stay as "YYYY-MM-DD" strings — lexicographic order is
/// chronological order, so no Date parsing is needed.
@MainActor
@Observable
final class RecentlyAddedService {
    private struct AddedDatesData: Decodable {
        let version: Int
        let generatedDate: String
        let tokenAddedDates: [String: String]
    }

    private static let schemaVersion = 1

    private(set) var addedDates: [String: String] = [:]

    /// Best-effort fetch, silent on failure — Recently Added stays empty
    /// offline, which is moot since the catalog itself is network-backed.
    func refreshFromRemote() async {
        guard let remote = await CaskFlowReleases.fetch(AddedDatesData.self, asset: "added_dates.json"),
              remote.version == Self.schemaVersion
        else { return }

        addedDates = remote.tokenAddedDates
    }

    /// Tokens added to Homebrew within the given number of days.
    func recentTokens(within days: Int) -> Set<String> {
        let cutoff = Self.dateString(daysAgo: days)
        return Set(addedDates.filter { $0.value >= cutoff }.keys)
    }

    /// "YYYY-MM-DD" the token entered homebrew-cask, or nil if unknown.
    func addedDate(for token: String) -> String? {
        addedDates[token]
    }

    private static func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return date.formatted(.iso8601.year().month().day())
    }
}
