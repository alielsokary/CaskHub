//
//  LocalHomebrewService+Pins.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/11/2026.
//

import Foundation

extension LocalHomebrewService {
    static let minimumPinningHomebrewVersion = "5.1.12"

    var supportsCaskPinning: Bool {
        brewVersion.flatMap {
            MaintenanceVersion.isCurrent(local: $0, latest: Self.minimumPinningHomebrewVersion)
        } ?? true
    }

    func pinnedVersion(for reference: String) -> String? {
        installationSnapshot.pinnedVersions[CaskReference.bareToken(reference)]
    }

    /// A leftover failed or awaiting state never blocks a pin; only queued or running work does.
    func canChangePin(for reference: String) -> Bool {
        operationStore.state(for: reference)?.action == nil && !pinChangesInFlight.contains(reference)
    }

    func setPinned(_ pinned: Bool, reference: String) async throws {
        guard canChangePin(for: reference) else { return }
        pinChangesInFlight.insert(reference)
        defer { pinChangesInFlight.remove(reference) }
        try await pinCommands.run(pinned: pinned, reference: reference)
        await refresh()
        await refreshHomebrewOutdated()
    }
}
