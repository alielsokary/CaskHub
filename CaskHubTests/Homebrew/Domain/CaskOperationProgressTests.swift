//
//  CaskOperationProgressTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 24/07/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

final class CaskOperationProgressTests: XCTestCase {
    func test_brew_progress_parser_reads_homebrew_byte_totals() throws {
        let output = "Cask docker-desktop    #######    Downloading    84.2MB/245.0MB"
        let progress = try XCTUnwrap(BrewProgressParser.parse(output).byteProgress)

        XCTAssertEqual(progress.completed, 84_200_000)
        XCTAssertEqual(progress.total, 245_000_000)
    }

    func test_byte_progress_uses_one_shared_unit() {
        let progress = CaskByteProgress(
            completedBytes: 46_300_000,
            totalBytes: 220_600_000
        )

        XCTAssertEqual(progress.text, "46.3 / 220.6 MB")
    }

    @MainActor
    func test_brew_output_updates_download_phase_then_install_phase() throws {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("operation-progress"))
        service.mutationCoordinator.beginOperation(
            .installing,
            token: "firefox",
            displayName: "Firefox"
        )
        service.operationStore.send(.setCancellable(true), for: "firefox")

        service.mutationCoordinator.consumeBrewOutput(
            "==> Downloading https://example.com/firefox.dmg",
            token: "firefox"
        )
        XCTAssertEqual(service.operationStore.state(for: "firefox")?.progress?.phase, .checkingDownload)
        XCTAssertEqual(
            service.operationStore.state(for: "firefox")?.progress?.inlineLabel,
            "Checking download…"
        )

        service.mutationCoordinator.consumeBrewOutput(
            "Cask firefox    ########    Downloading    42.0MB/100.0MB",
            token: "firefox"
        )
        let downloading = try XCTUnwrap(service.operationStore.state(for: "firefox")?.progress)
        XCTAssertEqual(downloading.phase, .downloading)
        XCTAssertEqual(downloading.completedBytes, 42_000_000)
        XCTAssertEqual(downloading.totalBytes, 100_000_000)
        XCTAssertEqual(try XCTUnwrap(downloading.fractionCompleted), 0.42, accuracy: 0.001)
        XCTAssertTrue(service.statusBarOperation?.message.contains("Downloading Firefox") == true)

        service.mutationCoordinator.consumeBrewOutput(
            "==> Installing Cask firefox",
            token: "firefox"
        )
        XCTAssertEqual(service.operationStore.state(for: "firefox")?.progress?.phase, .performing)
        XCTAssertFalse(service.operationStore.state(for: "firefox")?.canCancel == true)
    }

    @MainActor
    func test_rapid_progress_redraws_are_throttled_but_markers_parse_immediately() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("throttled-progress"))
        service.mutationCoordinator.beginOperation(
            .installing,
            token: "firefox",
            displayName: "Firefox"
        )

        service.mutationCoordinator.consumeBrewOutput(
            "Cask firefox    ####    Downloading    10.0MB/100.0MB",
            token: "firefox"
        )
        XCTAssertEqual(
            service.operationStore.state(for: "firefox")?.progress?.completedBytes,
            10_000_000
        )

        service.mutationCoordinator.consumeBrewOutput(
            "Cask firefox    ####    Downloading    20.0MB/100.0MB",
            token: "firefox"
        )
        XCTAssertEqual(
            service.operationStore.state(for: "firefox")?.progress?.completedBytes,
            10_000_000
        )

        service.mutationCoordinator.consumeBrewOutput(
            "==> Installing Cask firefox",
            token: "firefox"
        )
        XCTAssertEqual(
            service.operationStore.state(for: "firefox")?.progress?.phase,
            .performing
        )
    }

    @MainActor
    func test_brew_output_reports_cached_download_at_full_size() throws {
        let cachedDownload = FileManager.default.temporaryDirectory
            .appendingPathComponent("cached download-\(UUID().uuidString).dmg")
        try Data(repeating: 0, count: 2_048).write(to: cachedDownload)
        defer { try? FileManager.default.removeItem(at: cachedDownload) }

        let service = LocalHomebrewService(defaults: makeScratchDefaults("cached-progress"))
        service.mutationCoordinator.beginOperation(
            .installing,
            token: "chatgpt-classic",
            displayName: "ChatGPT Classic"
        )
        service.mutationCoordinator.consumeBrewOutput(
            """
            ==> Downloading https://example.com/ChatGPT_Classic.dmg
            Already downloaded: \(cachedDownload.path)
            """,
            token: "chatgpt-classic"
        )

        let progress = try XCTUnwrap(
            service.operationStore.state(for: "chatgpt-classic")?.progress
        )
        XCTAssertEqual(progress.phase, .usingCachedDownload)
        XCTAssertEqual(progress.completedBytes, 2_048)
        XCTAssertEqual(progress.totalBytes, 2_048)
        XCTAssertEqual(progress.fractionCompleted, 1)
        XCTAssertEqual(progress.inlineLabel, "Using cache · 2 / 2 KB")
    }

    func test_phase_parser_does_not_treat_download_preflight_as_byte_transfer() {
        let update = BrewProgressParser.parse(
            "==> Downloading https://example.com/ChatGPT_Classic.dmg"
        )

        XCTAssertEqual(update.phase, .checkingDownload)
        XCTAssertNil(update.byteProgress)
    }

    @MainActor
    func test_brew_output_updates_download_phase_then_upgrade_phase() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("update-progress"))
        service.mutationCoordinator.beginOperation(
            .updating,
            token: "firefox",
            displayName: "Firefox"
        )
        service.operationStore.send(.setCancellable(true), for: "firefox")

        service.mutationCoordinator.consumeBrewOutput(
            """
            ==> Upgrading firefox
            Cask firefox    ########    Downloading    100.0MB/100.0MB
            """,
            token: "firefox"
        )
        XCTAssertEqual(service.operationStore.state(for: "firefox")?.progress?.phase, .downloading)

        service.mutationCoordinator.consumeBrewOutput(
            "==> Upgrading firefox",
            token: "firefox"
        )
        XCTAssertEqual(service.operationStore.state(for: "firefox")?.progress?.phase, .performing)
        XCTAssertFalse(service.operationStore.state(for: "firefox")?.canCancel == true)
    }

    func test_operation_status_summarizes_multiple_operations() {
        let operations = [
            CaskOperationProgress(
                token: "docker",
                displayName: "Docker Desktop",
                action: .installing,
                phase: .downloading,
                completedBytes: 84_000_000,
                totalBytes: 245_000_000
            ),
            CaskOperationProgress(
                token: "firefox",
                displayName: "Firefox",
                action: .updating,
                phase: .performing
            )
        ]

        XCTAssertEqual(
            CaskOperationStatus.make(operations: operations, updateAll: nil)?.message,
            "2 operations in progress · 1 downloading · 1 updating"
        )
    }

    func test_operation_status_appends_current_update_all_download() {
        let operation = CaskOperationProgress(
            token: "docker",
            displayName: "Docker Desktop",
            action: .updating,
            phase: .downloading,
            completedBytes: 84_000_000,
            totalBytes: 245_000_000
        )
        let updateAll = CaskUpdateAllProgress(
            currentIndex: 3,
            totalCount: 8,
            currentToken: "docker",
            currentDisplayName: "Docker Desktop"
        )
        let message = CaskOperationStatus.make(
            operations: [operation],
            updateAll: updateAll
        )?.message

        XCTAssertEqual(
            message,
            "Updating 3 of 8 · Docker Desktop · 84 / 245 MB"
        )
    }

    @MainActor
    func test_progress_capsule_and_status_bar_render() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("progress-render"))
        service.mutationCoordinator.beginOperation(
            .installing,
            token: "plain",
            displayName: "Plain"
        )
        service.mutationCoordinator.consumeBrewOutput(
            "Cask plain    ########    Downloading    84.0MB/245.0MB",
            token: "plain"
        )

        render(CaskActionsView(cask: makeCask("plain")).environment(service))
        render(CaskActionsView(cask: makeCask("plain"), fullWidth: false).environment(service))
        render(
            StatusBarView(
                caskCount: 3_781,
                caskFlowRelease: "caskflow-v2026.07.18",
                operation: service.statusBarOperation
            )
        )
        render(
            ObservedStatusBarView(
                caskCount: 3_781,
                caskFlowRelease: "caskflow-v2026.07.18"
            )
            .environment(service)
        )
    }

    @MainActor
    private func render(_ view: some View, width: CGFloat = 420, height: CGFloat = 400) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
    }
}
