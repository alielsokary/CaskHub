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
        let progress = try XCTUnwrap(BrewProgressParser.byteProgress(in: output))

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
        service.caskDisplayNames["firefox"] = "Firefox"
        service.beginOperation(.installing, token: "firefox")
        service.cancellableDownloads.insert("firefox")

        service.consumeBrewOutput(
            "Cask firefox    ########    Downloading    42.0MB/100.0MB",
            token: "firefox"
        )
        let downloading = try XCTUnwrap(service.operationProgress["firefox"])
        XCTAssertEqual(downloading.phase, .downloading)
        XCTAssertEqual(downloading.completedBytes, 42_000_000)
        XCTAssertEqual(downloading.totalBytes, 100_000_000)
        XCTAssertEqual(try XCTUnwrap(downloading.fractionCompleted), 0.42, accuracy: 0.001)
        XCTAssertTrue(service.statusBarOperation?.message.contains("Downloading Firefox") == true)

        service.consumeBrewOutput("==> Installing Cask firefox", token: "firefox")
        XCTAssertEqual(service.operationProgress["firefox"]?.phase, .performing)
        XCTAssertFalse(service.cancellableDownloads.contains("firefox"))
    }

    @MainActor
    func test_brew_output_updates_download_phase_then_upgrade_phase() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("update-progress"))
        service.beginOperation(.updating, token: "firefox")
        service.cancellableDownloads.insert("firefox")

        service.consumeBrewOutput(
            """
            ==> Upgrading firefox
            Cask firefox    ########    Downloading    100.0MB/100.0MB
            """,
            token: "firefox"
        )
        XCTAssertEqual(service.operationProgress["firefox"]?.phase, .downloading)

        service.consumeBrewOutput("==> Upgrading firefox", token: "firefox")
        XCTAssertEqual(service.operationProgress["firefox"]?.phase, .performing)
        XCTAssertFalse(service.cancellableDownloads.contains("firefox"))
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
        service.beginOperation(.installing, token: "plain")
        service.consumeBrewOutput(
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
    }

    @MainActor
    private func render(_ view: some View, width: CGFloat = 420, height: CGFloat = 400) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
    }
}
