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
    private nonisolated struct AddedDatesData: Decodable {
        let version: Int
        let generatedDate: String
        let tokenAddedDates: [String: String]
    }

    private static let schemaVersion = 1

    var addedDates: [String: String] = [:] {
        didSet { catalogStateRevision &+= 1 }
    }
    private(set) var generatedDate = ""
    private(set) var catalogStateRevision = 0

    func loadBundledDates(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "added_dates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let bundled = try? JSONDecoder().decode(AddedDatesData.self, from: data),
              bundled.version == Self.schemaVersion
        else { return }

        apply(bundled)
    }

    /// Off-main decode; never overwrites fresher remote data.
    func loadBundledDatesAsync() async {
        guard let bundled = await Self.decodeBundledDates(),
              bundled.version == Self.schemaVersion,
              bundled.generatedDate > generatedDate
        else { return }
        apply(bundled)
    }

    @concurrent private static func decodeBundledDates() async -> AddedDatesData? {
        guard let url = Bundle.main.url(forResource: "added_dates", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(AddedDatesData.self, from: data)
    }

    func refreshFromRemote() async {
        guard let remote = await CaskFlowReleases.fetch(AddedDatesData.self, asset: "added_dates.json"),
              remote.version == Self.schemaVersion,
              remote.generatedDate > generatedDate
        else { return }

        apply(remote)
    }

    func recentTokens(within days: Int) -> Set<String> {
        let cutoff = Self.dateString(daysAgo: days)
        return Set(addedDates.filter { $0.value >= cutoff }.keys)
    }

    private static func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return date.formatted(.iso8601.year().month().day())
    }

    private func apply(_ data: AddedDatesData) {
        addedDates = data.tokenAddedDates
        generatedDate = data.generatedDate
    }
}
