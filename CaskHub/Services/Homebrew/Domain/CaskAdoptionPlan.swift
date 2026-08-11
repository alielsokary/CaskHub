//
//  CaskAdoptionPlan.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/08/2026.
//

import Foundation

nonisolated enum CaskAdoptionArtifact: Equatable, Sendable {
    case applicationBundle
    case packageInstaller
}

nonisolated enum CaskAdoptionVersionRelationship: Equatable, Sendable {
    case same
    case homebrewNewer
    case homebrewOlder
    case unknown
}

nonisolated enum CaskAdoptionOperation: Equatable, Sendable {
    case adopt
    case updateAndAdopt
    case downgradeAndAdopt
}

nonisolated enum CaskAdoptionExecution: Equatable, Sendable {
    case adoptApplication
    case replaceApplication
    case installPackage
    case replacePackage
}

nonisolated struct CaskAdoptionPlan: Equatable, Sendable {
    let artifact: CaskAdoptionArtifact
    let versionRelationship: CaskAdoptionVersionRelationship
    let operation: CaskAdoptionOperation
    let execution: CaskAdoptionExecution
    let installedVersion: String?
    let homebrewVersion: String
    let blockingInstalledCask: String?

    static func make(
        installationSource: CaskInstallationSource?,
        installedVersion: String?,
        homebrewVersion: String,
        installedCaskTokens: Set<String>,
        conflictingCaskTokens: [String]
    ) -> CaskAdoptionPlan? {
        guard let artifact = artifact(for: installationSource) else { return nil }
        let relationship = versionRelationship(
            installedVersion: installedVersion,
            homebrewVersion: homebrewVersion
        )
        return CaskAdoptionPlan(
            artifact: artifact,
            versionRelationship: relationship,
            operation: operation(for: relationship),
            execution: execution(for: artifact, relationship: relationship),
            installedVersion: installedVersion,
            homebrewVersion: homebrewVersion,
            blockingInstalledCask: conflictingCaskTokens
                .filter(installedCaskTokens.contains)
                .sorted()
                .first
        )
    }

    private static func artifact(
        for source: CaskInstallationSource?
    ) -> CaskAdoptionArtifact? {
        switch source {
        case .externalApplication: .applicationBundle
        case .packageInstaller: .packageInstaller
        case .homebrew, .macAppStore, .externalExecutable, nil: nil
        }
    }

    private static func operation(
        for relationship: CaskAdoptionVersionRelationship
    ) -> CaskAdoptionOperation {
        switch relationship {
        case .same, .unknown: .adopt
        case .homebrewNewer: .updateAndAdopt
        case .homebrewOlder: .downgradeAndAdopt
        }
    }

    private static func execution(
        for artifact: CaskAdoptionArtifact,
        relationship: CaskAdoptionVersionRelationship
    ) -> CaskAdoptionExecution {
        switch (artifact, relationship) {
        case (.applicationBundle, .same), (.applicationBundle, .unknown):
            .adoptApplication
        case (.applicationBundle, .homebrewNewer), (.applicationBundle, .homebrewOlder):
            .replaceApplication
        case (.packageInstaller, .same), (.packageInstaller, .homebrewOlder):
            .replacePackage
        case (.packageInstaller, .homebrewNewer),
             (.packageInstaller, .unknown):
            .installPackage
        }
    }

    private static func versionRelationship(
        installedVersion: String?,
        homebrewVersion: String
    ) -> CaskAdoptionVersionRelationship {
        guard let installedVersion,
              let comparison = NumericVersionComparison.compare(
                  installedVersion,
                  homebrewVersion
              )
        else { return .unknown }

        switch comparison {
        case .orderedSame: return .same
        case .orderedAscending: return .homebrewNewer
        case .orderedDescending: return .homebrewOlder
        }
    }
}

nonisolated struct CaskAdoptionRequest: Equatable, Sendable {
    let cask: Cask
    let plan: CaskAdoptionPlan
}

nonisolated enum NumericVersionComparison {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        guard let lhsComponents = components(in: lhs),
              let rhsComponents = components(in: rhs)
        else { return nil }

        for index in 0 ..< max(lhsComponents.count, rhsComponents.count) {
            let left = index < lhsComponents.count ? lhsComponents[index] : 0
            let right = index < rhsComponents.count ? rhsComponents[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(in version: String) -> [UInt64]? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let numericPrefix = trimmed.prefix { $0.isNumber || $0 == "." }
        guard !numericPrefix.isEmpty else { return nil }

        let parts = numericPrefix.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        let components = parts.compactMap { UInt64($0) }
        return components.count == parts.count ? components : nil
    }
}
