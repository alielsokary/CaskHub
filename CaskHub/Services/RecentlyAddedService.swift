//
//  RecentlyAddedService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/07/2026.
//

import Foundation
import Observation

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

@MainActor
@Observable
final class RecentlyAddedService {
    private struct AddedDatesData: Decodable {
        let version: Int
        let generatedDate: String
        let tokenAddedDates: [String: String]
    }

    private static let schemaVersion = 1

    var addedDates: [String: String] = [:]

    func refreshFromRemote() async {
        guard let remote = await CaskFlowReleases.fetch(AddedDatesData.self, asset: "added_dates.json"),
              remote.version == Self.schemaVersion
        else { return }

        addedDates = remote.tokenAddedDates
    }

    func recentTokens(within days: Int) -> Set<String> {
        let cutoff = Self.dateString(daysAgo: days)
        return Set(addedDates.filter { $0.value >= cutoff }.keys)
    }

    func addedDate(for token: String) -> String? {
        addedDates[token]
    }

    private static func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return date.formatted(.iso8601.year().month().day())
    }
}
