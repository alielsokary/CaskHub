//
//  CaskListActionTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 25/07/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

@MainActor
final class CaskListActionTests: XCTestCase {
    private final class ActionRecorder {
        var calls: [String] = []
    }

    private func makeImageCache() -> ImageCacheService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestRecordingProtocol.self]
        let cache = ImageCacheService(session: URLSession(configuration: configuration))
        cache.knownIconTokens = { [] }
        return cache
    }

    @discardableResult
    private func render(
        _ view: some View,
        width: CGFloat = 760,
        height: CGFloat = 64
    ) -> NSHostingView<AnyView> {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func row(
        _ cask: Cask,
        service: LocalHomebrewService,
        downloads: String? = "1.2M"
    ) -> some View {
        CaskRowView(cask: cask, downloads: downloads)
            .environment(service)
            .environment(makeImageCache())
    }

    private func menuButton(
        showsUpdate: Bool,
        isBusy: Bool = false,
        uninstallAvailability: CaskUninstallAvailability,
        recorder: ActionRecorder = ActionRecorder()
    ) -> CaskRowActionsMenuButton {
        CaskRowActionsMenuButton(
            showsUpdate: showsUpdate,
            isBusy: isBusy,
            uninstallAvailability: uninstallAvailability,
            onInfo: { recorder.calls.append("info") },
            onUpdate: { recorder.calls.append("update") },
            onUninstall: { recorder.calls.append("uninstall") }
        )
    }

    func test_row_action_menu_only_shows_info_when_uninstall_does_not_apply() {
        let coordinator = menuButton(
            showsUpdate: false,
            uninstallAvailability: .notApplicable
        ).makeCoordinator()

        let menu = coordinator.makeMenu()

        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertEqual(menu.items.map(\.title), ["Info"])
        XCTAssertTrue(menu.items[0].isEnabled)
        XCTAssertNotNil(menu.items[0].image)
    }

    func test_row_action_menu_enables_available_actions_and_invokes_callbacks() {
        let recorder = ActionRecorder()
        let coordinator = menuButton(
            showsUpdate: true,
            uninstallAvailability: .available,
            recorder: recorder
        ).makeCoordinator()

        let menu = coordinator.makeMenu()

        XCTAssertEqual(menu.items.map(\.title), ["Info", "Update", "", "Uninstall"])
        XCTAssertTrue(menu.items[1].isEnabled)
        XCTAssertNil(menu.items[1].toolTip)
        XCTAssertTrue(menu.items[3].isEnabled)
        XCTAssertNil(menu.items[3].toolTip)
        XCTAssertNotNil(menu.items[1].image)
        XCTAssertNotNil(menu.items[3].image)

        coordinator.showInfo()
        coordinator.update()
        coordinator.uninstall()
        XCTAssertEqual(recorder.calls, ["info", "update", "uninstall"])
    }

    func test_row_action_menu_disables_update_and_uninstall_while_busy() {
        let coordinator = menuButton(
            showsUpdate: true,
            isBusy: true,
            uninstallAvailability: .available
        ).makeCoordinator()

        let menu = coordinator.makeMenu()
        let expectedHint = "Wait for the current action to finish."

        XCTAssertFalse(menu.items[1].isEnabled)
        XCTAssertEqual(menu.items[1].toolTip, expectedHint)
        XCTAssertFalse(menu.items[3].isEnabled)
        XCTAssertEqual(menu.items[3].toolTip, expectedHint)
    }

    func test_row_action_menu_preserves_unavailable_uninstall_hint() {
        let hint = "Adopt this app first so CaskHub can manage/uninstall it."
        let coordinator = menuButton(
            showsUpdate: false,
            uninstallAvailability: .unavailable(reason: hint)
        ).makeCoordinator()

        let menu = coordinator.makeMenu()

        XCTAssertEqual(menu.items.map(\.title), ["Info", "", "Uninstall"])
        XCTAssertFalse(menu.items[2].isEnabled)
        XCTAssertEqual(menu.items[2].toolTip, hint)
    }

    func test_list_rows_render_install_and_external_installation_states() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("list-external"))
        updateInstallationSnapshot(
            of: service,
            externalAppNames: ["Adoptable.app"],
            macAppStoreAppNames: ["Store.app"],
            externalBinaryPaths: [
                "native-cli": URL(fileURLWithPath: "/usr/local/bin/native-cli")
            ]
        )

        render(row(makeCask("plain", desc: "A new app"), service: service))
        render(row(makeCask("adoptable", appNames: ["Adoptable.app"]), service: service))
        render(row(makeCask("store", appNames: ["Store.app"]), service: service))
        render(row(makeCask("native", binaryNames: ["native-cli"]), service: service, downloads: nil))
    }

    func test_list_rows_render_every_managed_action_layout() throws {
        let applications = FileManager.default.temporaryDirectory
            .appendingPathComponent("list-action-apps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: applications) }
        try makeApplicationBundle(
            in: applications,
            named: "Managed.app",
            bundleIdentifier: "test.managed"
        )

        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("list-managed"),
            applicationDirectories: [applications]
        )
        let managed = makeCask("managed", desc: "Managed app", appNames: ["Managed.app"])
        updateInstalledCask(LocalCaskInstallation(
            token: managed.token,
            installedVersion: "1.0",
            installedAt: nil,
            appBundleNames: ["Managed.app"]
        ), in: service)

        render(row(managed, service: service))
        render(row(makeCask("managed", version: "2.0", appNames: ["Managed.app"]), service: service))

        service.operationStore.send(.enqueue(.updating), for: managed.token)
        render(row(managed, service: service))
        service.operationStore.send(.clear, for: managed.token)

        let installedOnly = makeCask("installed-only")
        updateInstalledCask(installation(installedOnly.token, version: "1.0"), in: service)
        render(row(installedOnly, service: service))

        let updateOnly = makeCask("update-only", version: "2.0")
        updateInstalledCask(installation(updateOnly.token, version: "1.0"), in: service)
        render(row(updateOnly, service: service))

        let zombie = makeCask("zombie", appNames: ["Missing.app"])
        updateInstalledCask(LocalCaskInstallation(
            token: zombie.token,
            installedVersion: "1.0",
            installedAt: nil,
            appBundleNames: ["Missing.app"],
            isZombie: true
        ), in: service)
        render(row(zombie, service: service))
    }

    func test_icon_only_open_and_update_controls_render() {
        render(
            HStack {
                ActionCapsuleIconButton(action: .open) {}
                ActionCapsuleIconButton(action: .update) {}
            }
        )
    }
}
