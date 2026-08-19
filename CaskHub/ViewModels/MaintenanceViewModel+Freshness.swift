//
//  MaintenanceViewModel+Freshness.swift
//  CaskHub
//
//  Created by Ali Elsokary on 19/08/2026.
//

import Foundation

extension MaintenanceViewModel {
    private static let releaseCheckedAtKey = "maintenanceReleaseCheckedAt"
    private static let latestBrewTagKey = "maintenanceLatestBrewTag"
    private static let latestCaskFlowTagKey = "maintenanceLatestCaskFlowTag"
    private static let releaseCheckMaxAge: TimeInterval = 3600

    var caskFlowReleaseTag: String? { catalog.categoryService.releaseTag }

    func refreshFreshness(force: Bool = false) async {
        let checkedAt = defaults.object(forKey: Self.releaseCheckedAtKey) as? Date
        let isStale = checkedAt.map {
            Date.now.timeIntervalSince($0) >= Self.releaseCheckMaxAge
        } ?? true
        if force || isStale {
            let brewTag = await latestReleaseTag("Homebrew", "brew")
            let caskFlowTag = await latestReleaseTag("alielsokary", "CaskFlow")
            if let brewTag { defaults.set(brewTag, forKey: Self.latestBrewTagKey) }
            if let caskFlowTag {
                defaults.set(caskFlowTag, forKey: Self.latestCaskFlowTagKey)
            }
            if brewTag != nil || caskFlowTag != nil {
                defaults.set(Date.now, forKey: Self.releaseCheckedAtKey)
            }
        }
        recomputeFreshness()
    }

    private func recomputeFreshness() {
        if let latest = defaults.string(forKey: Self.latestBrewTagKey),
           let local = localHomebrew.brewVersion,
           let isCurrent = MaintenanceVersion.isCurrent(local: local, latest: latest) {
            brewFreshness = isCurrent
                ? .current
                : .updateAvailable(MaintenanceVersion.normalized(latest))
        } else {
            brewFreshness = .unknown
        }
        if let latest = defaults.string(forKey: Self.latestCaskFlowTagKey),
           let loaded = caskFlowReleaseTag {
            collectionFreshness = MaintenanceVersion.normalized(loaded)
                == MaintenanceVersion.normalized(latest)
                ? .current
                : .updateAvailable(MaintenanceVersion.normalized(latest))
        } else {
            collectionFreshness = .unknown
        }
    }
}
