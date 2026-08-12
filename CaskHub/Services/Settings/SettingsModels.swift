//
//  SettingsModels.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation
import Observation
import ServiceManagement

@MainActor
protocol LoginItemManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct SystemLoginItemManager: LoginItemManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
protocol AppManagementPermissionProviding {
    func currentStatus() async -> AppManagementPermission.Status
    func openSystemSettings()
}

@MainActor
struct SystemAppManagementPermissionProvider: AppManagementPermissionProviding {
    func currentStatus() async -> AppManagementPermission.Status {
        await Task.detached(priority: .utility) {
            AppManagementPermission.probe()
        }.value
    }

    func openSystemSettings() {
        AppManagementPermission.openSystemSettings()
    }
}

@MainActor
@Observable
final class GeneralSettingsModel {
    private(set) var launchAtLogin: Bool
    private(set) var appManagement: AppManagementPermission.Status = .unknown

    private let loginItemManager: any LoginItemManaging
    private let permissionProvider: any AppManagementPermissionProviding

    init(
        loginItemManager: (any LoginItemManaging)? = nil,
        permissionProvider: (any AppManagementPermissionProviding)? = nil
    ) {
        let loginItemManager = loginItemManager ?? SystemLoginItemManager()
        self.loginItemManager = loginItemManager
        self.permissionProvider = permissionProvider
            ?? SystemAppManagementPermissionProvider()
        launchAtLogin = loginItemManager.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemManager.setEnabled(enabled)
            launchAtLogin = loginItemManager.isEnabled
        } catch {
            CrashReporter.capture(error)
            launchAtLogin = loginItemManager.isEnabled
        }
    }

    func refreshAppManagement() async {
        appManagement = await permissionProvider.currentStatus()
    }

    func openAppManagementSettings() {
        permissionProvider.openSystemSettings()
    }
}

nonisolated protocol HomebrewLocationResolving: Sendable {
    func prefix(from selection: URL) -> String?
}

nonisolated struct SystemHomebrewLocationResolver: HomebrewLocationResolving {
    func prefix(from selection: URL) -> String? {
        HomebrewLocator.prefix(from: selection)
    }
}

nonisolated enum HomebrewLocationChoice: Hashable, Sendable {
    case appleSilicon
    case intel
    case custom

    var prefix: String? {
        switch self {
        case .appleSilicon:
            HomebrewLocator.appleSiliconPrefix
        case .intel:
            HomebrewLocator.intelPrefix
        case .custom:
            nil
        }
    }

    var brewBinaryPath: String? {
        prefix.map { "\($0)/bin/brew" }
    }
}

@MainActor
protocol HomebrewSettingsApplying: AnyObject {
    var customBrewPrefix: String? { get }
    func setCustomBrewPrefix(_ prefix: String?) async
}

extension LocalHomebrewService: HomebrewSettingsApplying {}

@MainActor
@Observable
final class HomebrewLocationSettingsModel {
    var selection: HomebrewLocationChoice
    var customPathField: String
    private(set) var invalidSelection = false

    private let settings: any HomebrewSettingsApplying
    private let resolver: any HomebrewLocationResolving
    private let machineIsAppleSilicon: Bool

    init(
        settings: any HomebrewSettingsApplying,
        resolver: any HomebrewLocationResolving = SystemHomebrewLocationResolver(),
        machineIsAppleSilicon: Bool = HomebrewLocator.isAppleSilicon
    ) {
        self.settings = settings
        self.resolver = resolver
        self.machineIsAppleSilicon = machineIsAppleSilicon
        selection = machineIsAppleSilicon ? .appleSilicon : .intel
        customPathField = ""
        synchronize()
    }

    func synchronize() {
        let configuredPrefix = settings.customBrewPrefix
        selection = Self.choice(
            for: configuredPrefix,
            machineIsAppleSilicon: machineIsAppleSilicon
        )
        let nativePrefix = machineIsAppleSilicon
            ? HomebrewLocator.appleSiliconPrefix
            : HomebrewLocator.intelPrefix
        customPathField = selection == .custom
            ? Self.brewBinaryPath(for: configuredPrefix ?? "")
            : Self.brewBinaryPath(for: nativePrefix)
        invalidSelection = validatedPrefix(for: selection.prefix ?? customPathField) == nil
    }

    func applyChoice(_ choice: HomebrewLocationChoice) async {
        selection = choice
        guard let prefix = choice.prefix else {
            invalidSelection = validatedPrefix(for: customPathField) == nil
            return
        }
        await apply(path: prefix)
    }

    func applyTypedPath() async {
        selection = .custom
        await apply(path: customPathField)
    }

    func applySelection(_ selection: URL) async {
        self.selection = .custom
        customPathField = selection.path
        await apply(path: selection.path)
    }

    func validateCustomPath() {
        guard selection == .custom else { return }
        invalidSelection = validatedPrefix(for: customPathField) == nil
    }

    private func apply(path: String) async {
        guard let prefix = validatedPrefix(for: path) else {
            invalidSelection = true
            return
        }
        await apply(prefix: prefix)
    }

    private func validatedPrefix(for path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let prefix = resolver.prefix(from: URL(fileURLWithPath: trimmed)),
              HomebrewLocator.isCompatible(
                brewURL: URL(fileURLWithPath: prefix).appendingPathComponent("bin/brew"),
                machineIsAppleSilicon: machineIsAppleSilicon
              )
        else { return nil }
        return prefix
    }

    private func apply(prefix: String) async {
        invalidSelection = false
        await settings.setCustomBrewPrefix(prefix)
        synchronize()
    }

    private static func brewBinaryPath(for prefix: String) -> String {
        URL(fileURLWithPath: prefix).appendingPathComponent("bin/brew").path
    }

    private static func choice(
        for prefix: String?,
        machineIsAppleSilicon: Bool
    ) -> HomebrewLocationChoice {
        switch prefix.map({ URL(fileURLWithPath: $0).standardizedFileURL.path }) {
        case HomebrewLocator.appleSiliconPrefix:
            return .appleSilicon
        case HomebrewLocator.intelPrefix:
            return .intel
        case .some:
            return .custom
        case nil:
            return machineIsAppleSilicon ? .appleSilicon : .intel
        }
    }
}
