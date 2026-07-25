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
        LocalHomebrewService.brewPrefix(fromSelection: selection)
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
    var customPathField: String
    private(set) var invalidSelection = false

    private let settings: any HomebrewSettingsApplying
    private let resolver: any HomebrewLocationResolving

    init(
        settings: any HomebrewSettingsApplying,
        resolver: any HomebrewLocationResolving = SystemHomebrewLocationResolver()
    ) {
        self.settings = settings
        self.resolver = resolver
        customPathField = settings.customBrewPrefix ?? ""
    }

    func synchronize() {
        customPathField = settings.customBrewPrefix ?? ""
    }

    func applyTypedPath() async {
        let trimmed = customPathField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await apply(prefix: nil)
            return
        }
        await apply(selection: URL(fileURLWithPath: trimmed))
    }

    func applySelection(_ selection: URL) async {
        await apply(selection: selection)
    }

    func dismissInvalidSelection() {
        invalidSelection = false
    }

    private func apply(selection: URL) async {
        guard let prefix = resolver.prefix(from: selection) else {
            invalidSelection = true
            synchronize()
            return
        }
        await apply(prefix: prefix)
    }

    private func apply(prefix: String?) async {
        invalidSelection = false
        await settings.setCustomBrewPrefix(prefix)
        synchronize()
    }
}
