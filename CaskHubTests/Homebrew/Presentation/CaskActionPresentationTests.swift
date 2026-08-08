//
//  CaskActionPresentationTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 25/07/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

@MainActor
final class CaskActionPresentationTests: XCTestCase {
    func test_running_presentation_exposes_one_coherent_operation() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("presentation-running"))
        let cask = makeCask("firefox", name: "Firefox")
        service.mutationCoordinator.beginOperation(
            .installing,
            token: cask.token,
            displayName: cask.displayName
        )
        service.operationStore.send(.setCancellable(true), for: cask.token)

        let presentation = service.actionPresentation(for: cask)

        XCTAssertEqual(presentation.activeAction, .installing)
        XCTAssertEqual(presentation.progress?.token, cask.token)
        XCTAssertTrue(presentation.canCancel)
        XCTAssertTrue(presentation.isBusy)
        XCTAssertNil(service.actionAlert(for: cask.token))
    }

    func test_failure_presentation_carries_message_and_recovery_together() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("presentation-failure"))
        let cask = makeCask("tabby")
        let failure = CaskOperationFailure(
            kind: .brewCommand,
            message: "Repair is available",
            recoveries: [.repairAndReinstall]
        )
        service.operationStore.send(.fail(failure), for: cask.token)

        let presentation = service.actionPresentation(for: cask)

        XCTAssertEqual(service.actionAlert(for: cask.token), .failure(failure))
        XCTAssertFalse(presentation.isBusy)
        XCTAssertNil(presentation.activeAction)
    }

    func test_homebrew_missing_has_a_distinct_alert() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("presentation-brew"))
        let cask = makeCask("firefox")
        let failure = CaskOperationFailure(
            kind: .homebrewMissing,
            message: "Homebrew not found"
        )
        service.operationStore.send(.fail(failure), for: cask.token)

        XCTAssertEqual(
            service.actionAlert(for: cask.token),
            .homebrewMissing(message: "Homebrew not found")
        )
    }

    func test_alert_query_reads_only_the_operation_state_for_a_token() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("presentation-alert"))
        let failure = CaskOperationFailure(
            kind: .brewCommand,
            message: "Repair is available",
            recoveries: [.repairAndReinstall]
        )

        XCTAssertNil(service.actionAlert(for: "tabby"))

        service.operationStore.send(.fail(failure), for: "tabby")

        XCTAssertEqual(service.actionAlert(for: "tabby"), .failure(failure))
    }
}

final class AdoptionViewRenderTests: XCTestCase {
    @MainActor
    private func render(_ view: some View, width: CGFloat = 420, height: CGFloat = 400) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
    }

    @MainActor
    func test_cask_actions_render_every_external_state() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("render-actions"))
        updateInstallationSnapshot(of: service) {
            $0.installedCasks = [
                "managed": LocalCaskInstallation(
                    token: "managed",
                    installedVersion: "1.0",
                    installedAt: nil,
                    appBundleNames: ["Managed.app"]
                )
            ]
            $0.externalAppNames = ["Chrome.app"]
            $0.macAppStoreAppNames = ["Store.app"]
            $0.externalBinaryPaths = [
                "claude": URL(fileURLWithPath: "/usr/local/bin/claude")
            ]
        }

        let adoptable = makeCask("chrome", appNames: ["Chrome.app"])
        render(CaskActionsView(cask: adoptable).environment(service).environment(\.isAdoptPage, true))
        render(
            CaskActionsView(cask: adoptable, usesIconOnlyOpenAndUpdate: true)
                .environment(service)
        )
        render(CaskActionsView(cask: makeCask("store", appNames: ["Store.app"])).environment(service))
        render(CaskActionsView(cask: makeCask("claude-code", binaryNames: ["claude"])).environment(service))
        render(CaskActionsView(cask: makeCask("plain")).environment(service))
        render(
            CaskActionsView(cask: makeCask("managed", version: "2.0"), onUninstall: {})
                .environment(service)
        )
    }

    @MainActor
    func test_cask_action_alerts_render_with_pending_permission_and_error() async {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("render-alerts"))
        service.permissionProbe = { .denied }
        try? await service.adopt(token: "chrome")
        service.open(makeCask("chrome"))

        render(
            Text("host")
                .caskActionAlerts(for: makeCask("chrome"), showUninstallConfirmation: .constant(false))
                .environment(service)
        )
    }

    @MainActor
    func test_info_popover_renders_external_and_installed_versions() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("render-popover"))
        render(
            CaskInfoPopover(
                cask: makeCask("mystery", appNames: ["NoSuchApp.app"]),
                category: nil
            )
            .environment(service)
        )

        updateInstalledCask(LocalCaskInstallation(
            token: "known", installedVersion: "3.1", installedAt: .now, appBundleNames: []
        ), in: service)
        render(CaskInfoPopover(cask: makeCask("known"), category: nil).environment(service))
    }

    @MainActor
    func test_uninstall_alert_shows_copyable_command_with_destructive_button() {
        let alert = CaskActionAlertFactory.uninstallAlert(for: makeCask("iina", name: "IINA"))

        XCTAssertEqual(alert.messageText, "Uninstall IINA?")
        XCTAssertEqual(alert.informativeText, "This will run:")
        XCTAssertNotNil(alert.accessoryView)
        XCTAssertEqual(alert.buttons.map(\.title), ["Uninstall", "Cancel"])
        XCTAssertTrue(alert.buttons[0].hasDestructiveAction)
    }

    @MainActor
    func test_error_alert_orders_recovery_buttons_before_ok() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("alert-buttons"))
        let failure = CaskOperationFailure(
            kind: .brewCommand,
            message: "short message",
            recoveries: [.replaceWithHomebrew, .adoptExisting]
        )

        let (alert, actions) = CaskActionAlertFactory.errorAlert(
            for: makeCask("wireshark-app", name: "Wireshark"), failure: failure, service: service
        )

        XCTAssertEqual(alert.messageText, "Wireshark Failed")
        XCTAssertEqual(alert.informativeText, "short message")
        XCTAssertNil(alert.accessoryView)
        XCTAssertEqual(
            alert.buttons.map(\.title),
            ["Adopt Existing App", "Replace with Homebrew Version", "OK"]
        )
        XCTAssertEqual(actions.count, alert.buttons.count)
    }

    @MainActor
    func test_error_alert_scrolls_long_output_instead_of_growing() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("alert-scroll"))
        let message = String(repeating: "brew output line\n", count: 60)
        let failure = CaskOperationFailure(kind: .brewCommand, message: message)

        let (alert, _) = CaskActionAlertFactory.errorAlert(
            for: makeCask("kdrive"), failure: failure, service: service
        )

        XCTAssertEqual(alert.informativeText, "")
        let scroll = try? XCTUnwrap(alert.accessoryView as? NSScrollView)
        let textView = scroll?.documentView as? NSTextView
        XCTAssertEqual(textView?.string, message)
        XCTAssertEqual(textView?.isEditable, false)
        XCTAssertLessThanOrEqual(scroll?.frame.height ?? .infinity, 200)
    }

    @MainActor
    func test_error_alert_covers_every_recovery_button_title_and_action() async {
        let runner = StubBrewProcessRunner()
        let service = LocalHomebrewService(defaults: makeScratchDefaults("alert-titles")) {
            $0.fileManager = NoFilesFileManager()
            $0.processRunner = runner
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
        }
        service.permissionProbe = { .denied }
        let failure = CaskOperationFailure(
            kind: .brewCommand,
            message: "short",
            recoveries: Set(CaskRecoveryAction.allCases)
        )

        let (alert, actions) = CaskActionAlertFactory.errorAlert(
            for: makeCask("firefox"), failure: failure, service: service
        )

        XCTAssertEqual(alert.buttons.map(\.title), [
            "Adopt Existing App",
            "Replace with Homebrew Version",
            "Repair & Reinstall",
            "Force Uninstall",
            "Open System Settings",
            "OK"
        ])
        XCTAssertEqual(actions.count, 6)

        // Every action except Open System Settings (launches the real app) and OK.
        for action in actions[0...3] {
            action()
            try? await Task.sleep(for: .milliseconds(150))
        }
        XCTAssertTrue(
            runner.requests.contains { $0.arguments.contains("--force") },
            "force uninstall reached the runner"
        )
        actions.last?()
    }
}
