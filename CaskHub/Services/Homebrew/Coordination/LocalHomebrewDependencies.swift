//
//  LocalHomebrewDependencies.swift
//  CaskHub
//
//  Created by Ali Elsokary on 26/07/2026.
//

import Foundation

nonisolated struct HomebrewMutationContext: Sendable {
    let adoptionPlan: CaskAdoptionPlan?
    let permissionEvidence: AppManagementPermission.Evidence?

    static let none = HomebrewMutationContext(
        adoptionPlan: nil,
        permissionEvidence: nil
    )

    var telemetryTags: [String: String] {
        guard let adoptionPlan else { return [:] }
        var tags = [
            "brew.adoption_relationship": adoptionPlan.versionRelationship.rawValue,
            "brew.adoption_execution": adoptionPlan.execution.rawValue
        ]
        tags["brew.permission_evidence"] = permissionEvidence?.rawValue
        return tags
    }
}

enum HomebrewIssuePolicy {
    static func shouldCapture(
        _ error: Error,
        action: CaskAction,
        context: HomebrewMutationContext
    ) -> Bool {
        guard let localError = error as? LocalHomebrewError else { return true }
        return shouldCaptureLocalError(
            localError,
            action: action,
            context: context
        )
    }

    private static func shouldCaptureLocalError(
        _ error: LocalHomebrewError,
        action: CaskAction,
        context: HomebrewMutationContext
    ) -> Bool {
        switch error {
        case .brewBinaryNotFound:
            return false
        case .incompatibleBrewPath, .appBundleNotFound:
            return true
        case let .askpassUnavailable(_, failureKind):
            return !failureKind.isNormallyExternal
        case let .brewCommandFailed(failure):
            return shouldCaptureCommandFailure(
                failure,
                action: action,
                context: context
            )
        }
    }

    private static func shouldCaptureCommandFailure(
        _ failure: HomebrewCommandFailure,
        action: CaskAction,
        context: HomebrewMutationContext
    ) -> Bool {
        if failure.kind.isExplicitUserDecision
            || failure.kind.isNormallyExternal {
            return false
        }
        guard action != .updatingHomebrew,
              failure.kind == .adoptVersionMismatch,
              let relationship = context.adoptionPlan?.versionRelationship else {
            return true
        }
        return relationship != .same && relationship != .unknown
    }
}

@MainActor
struct LocalHomebrewDependencies {
    var fileManager: FileManager = .default
    var applicationDirectories: [URL]?
    var processRunner: (any BrewProcessRunning)?
    var commandExecutor: (any HomebrewCommandExecuting)?
    var softwareScanner: (any InstalledSoftwareScanning)?
    var applicationLauncher: (any ApplicationLaunching)?
    var askpassProvider: @Sendable (String) async throws -> URL = {
        try await AskpassScriptManager.create(token: $0)
    }
    var brewBinaryProvider: () -> URL? = {
        HomebrewLocator.brewBinaryURL()
    }
    var brewVersionProvider: () async -> String? = {
        await HomebrewVersionLoader().load(
            from: HomebrewLocator.brewBinaryURL()
        )
    }

    func resolvedCommandExecutor() -> any HomebrewCommandExecuting {
        commandExecutor
            ?? SystemHomebrewCommandExecutor(
                processRunner: processRunner ?? SystemBrewProcessRunner()
            )
    }
}
