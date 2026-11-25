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
    var caskPlatformProvider: (() async -> CaskPlatform?)?
    var fileManager: FileManager = .default
    var notificationCenter: NotificationCenter = .default
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
    var homebrewOutdatedProvider: (() async -> HomebrewOutdatedReport?)?
    var tapIndexProvider: (() async -> TapIndex?)?
    var installedFormulaeProvider: ((String) async -> [String])?
    var tapUpdateProvider: (() async -> Void)?
    var tapTrustProvider: (() async -> TapTrust)?
    var laneLimiter: HomebrewLaneLimiter?
    var fetchStallTimeout: Duration = .seconds(50)

    func resolvedCommandExecutor() -> any HomebrewCommandExecuting {
        commandExecutor
            ?? SystemHomebrewCommandExecutor(
                processRunner: processRunner ?? SystemBrewProcessRunner()
            )
    }

    func resolvedApplicationDirectories() -> [URL] {
        applicationDirectories ?? ApplicationDiscovery.defaultDirectories(fileManager: fileManager)
    }

    func resolvedApplicationLauncher() -> any ApplicationLaunching {
        applicationLauncher ?? WorkspaceApplicationLauncher()
    }

    func resolvedSoftwareScanner() -> any InstalledSoftwareScanning {
        softwareScanner ?? HomebrewInstallationScanner()
    }

    func resolvedCaskPlatformProvider() -> () async -> CaskPlatform? {
        let brewBinary = brewBinaryProvider
        return caskPlatformProvider ?? { await HomebrewPlatformLoader().load(from: brewBinary()) }
    }

    func resolvedHomebrewOutdatedProvider() -> () async -> HomebrewOutdatedReport? {
        let brewBinary = brewBinaryProvider
        return homebrewOutdatedProvider ?? { await HomebrewOutdatedLoader().load(from: brewBinary()) }
    }

    func resolvedTapIndexProvider() -> () async -> TapIndex? {
        let tapBrew = tapBrewProvider
        return tapIndexProvider ?? { await HomebrewTapLoader().load(from: tapBrew()) }
    }

    func resolvedInstalledFormulaeProvider() -> (String) async -> [String] {
        let tapBrew = tapBrewProvider
        return installedFormulaeProvider ?? { await HomebrewTapLoader().installedFormulae(in: $0, from: tapBrew()) }
    }

    func resolvedTapTrustProvider() -> () async -> TapTrust {
        let tapBrew = tapBrewProvider
        return tapTrustProvider ?? { await HomebrewTapLoader().trust(from: tapBrew()) }
    }

    func resolvedTapUpdateProvider() -> () async -> Void {
        let tapBrew = tapBrewProvider
        return tapUpdateProvider ?? { await HomebrewTapLoader().update(from: tapBrew()) }
    }

    // The test host app must never run real tap or trust queries; tests inject their own.
    private var tapBrewProvider: () -> URL? {
        let brewBinary = brewBinaryProvider
        return { CrashReporter.isRunningTests ? nil : brewBinary() }
    }
}
