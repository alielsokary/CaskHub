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
    func test_brew_output_updates_download_phase_then_install_phase() async throws {
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
        await service.mutationCoordinator.awaitPendingOutput()
        XCTAssertEqual(service.operationStore.state(for: "firefox")?.progress?.phase, .checkingDownload)
        let checkingLabel = CaskOperationPhase.checkingDownload.label(for: .installing)
        XCTAssertEqual(
            service.operationStore.state(for: "firefox")?.progress?.inlineLabel,
            "\(checkingLabel)…"
        )

        service.mutationCoordinator.consumeBrewOutput(
            "Cask firefox    ########    Downloading    42.0MB/100.0MB",
            token: "firefox"
        )
        await service.mutationCoordinator.awaitPendingOutput()
        let downloading = try XCTUnwrap(service.operationStore.state(for: "firefox")?.progress)
        XCTAssertEqual(downloading.phase, .downloading)
        XCTAssertEqual(downloading.completedBytes, 42_000_000)
        XCTAssertEqual(downloading.totalBytes, 100_000_000)
        XCTAssertEqual(try XCTUnwrap(downloading.fractionCompleted), 0.42, accuracy: 0.001)
        let downloadingLabel = CaskOperationPhase.downloading.label(for: .installing)
        XCTAssertTrue(
            service.statusBarOperation?.message.contains("\(downloadingLabel) Firefox") == true
        )

        service.mutationCoordinator.consumeBrewOutput(
            "==> Installing Cask firefox",
            token: "firefox"
        )
        await service.mutationCoordinator.awaitPendingOutput()
        XCTAssertEqual(service.operationStore.state(for: "firefox")?.progress?.phase, .performing)
        XCTAssertFalse(service.operationStore.state(for: "firefox")?.canCancel == true)
    }

    @MainActor
    func test_rapid_progress_redraws_are_throttled_but_markers_parse_immediately() async {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("throttled-progress"))
        service.mutationCoordinator.beginOperation(
            .installing,
            token: "firefox",
            displayName: "Firefox"
        )

        // Both chunks are enqueued before draining, so a slow main actor cannot outlast the throttle window.
        service.mutationCoordinator.consumeBrewOutput(
            "Cask firefox    ####    Downloading    10.0MB/100.0MB",
            token: "firefox"
        )
        service.mutationCoordinator.consumeBrewOutput(
            "Cask firefox    ####    Downloading    20.0MB/100.0MB",
            token: "firefox"
        )
        await service.mutationCoordinator.awaitPendingOutput()
        XCTAssertEqual(
            service.operationStore.state(for: "firefox")?.progress?.completedBytes,
            10_000_000
        )

        service.mutationCoordinator.consumeBrewOutput(
            "==> Installing Cask firefox",
            token: "firefox"
        )
        await service.mutationCoordinator.awaitPendingOutput()
        XCTAssertEqual(
            service.operationStore.state(for: "firefox")?.progress?.phase,
            .performing
        )
    }

    @MainActor
    func test_brew_output_reports_cached_download_at_full_size() async throws {
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
        await service.mutationCoordinator.awaitPendingOutput()

        let progress = try XCTUnwrap(
            service.operationStore.state(for: "chatgpt-classic")?.progress
        )
        XCTAssertEqual(progress.phase, .usingCachedDownload)
        XCTAssertEqual(progress.completedBytes, 2_048)
        XCTAssertEqual(progress.totalBytes, 2_048)
        XCTAssertEqual(progress.fractionCompleted, 1)
        let cacheLabel = CaskOperationPhase.usingCachedDownload.label(for: .installing)
        XCTAssertEqual(progress.inlineLabel, "\(cacheLabel) · 2 / 2 KB")
    }

    func test_phase_parser_does_not_treat_download_preflight_as_byte_transfer() {
        let update = BrewProgressParser.parse(
            "==> Downloading https://example.com/ChatGPT_Classic.dmg"
        )

        XCTAssertEqual(update.phase, .checkingDownload)
        XCTAssertNil(update.byteProgress)
    }

    func test_phase_parser_reads_homebrew_7_fetch_headings() {
        XCTAssertEqual(BrewProgressParser.parse("==> Fetching mole-app from homebrew/cask").phase, .connecting)
        XCTAssertEqual(BrewProgressParser.parse("==> Fetching downloads for: mole-app").phase, .verifying)
        XCTAssertNil(BrewProgressParser.parse("==> Fetching dependency downloads").phase)
    }

    @MainActor
    func test_fetch_connects_until_bytes_arrive_then_install_step_verifies() async {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("fetch-heading-progress"))
        service.mutationCoordinator.beginOperation(.installing, token: "mole-app", displayName: "Mole")
        func phase(after output: String) async -> CaskOperationPhase? {
            service.mutationCoordinator.consumeBrewOutput(output, token: "mole-app")
            await service.mutationCoordinator.awaitPendingOutput()
            return service.operationStore.state(for: "mole-app")?.progress?.phase
        }

        let connecting = await phase(after: "==> Fetching mole-app from homebrew/cask\n")
        XCTAssertEqual(connecting, .connecting)
        XCTAssertFalse(CaskOperationPhase.connecting.isDownloadActivity, "no bytes yet, so the capsule keeps the spinner")
        XCTAssertEqual(
            service.operationStore.state(for: "mole-app")?.progress?.inlineLabel,
            "\(CaskOperationPhase.connecting.label(for: .installing))…"
        )
        let downloading = await phase(after: "Cask mole-app    ##    Downloading    1.0MB/26.5MB\n")
        XCTAssertEqual(downloading, .downloading)
        let verifying = await phase(after: "✔︎ Cask mole-app (1.20.1)\n==> Fetching downloads for: mole-app\n")
        XCTAssertEqual(verifying, .verifying)
        let installing = await phase(after: "==> Installing Cask mole-app\n")
        XCTAssertEqual(installing, .performing)
    }

    @MainActor
    func test_brew_output_updates_download_phase_then_upgrade_phase() async {
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
        await service.mutationCoordinator.awaitPendingOutput()
        XCTAssertEqual(service.operationStore.state(for: "firefox")?.progress?.phase, .downloading)

        service.mutationCoordinator.consumeBrewOutput(
            "==> Upgrading firefox",
            token: "firefox"
        )
        await service.mutationCoordinator.awaitPendingOutput()
        XCTAssertEqual(service.operationStore.state(for: "firefox")?.progress?.phase, .performing)
        XCTAssertFalse(service.operationStore.state(for: "firefox")?.canCancel == true)
    }

    @MainActor
    func test_homebrew_update_begins_with_its_visible_update_label() throws {
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("homebrew-update-progress")
        )

        service.mutationCoordinator.beginOperation(
            .updatingHomebrew,
            token: "gimp",
            displayName: "Homebrew"
        )

        let progress = try XCTUnwrap(
            service.operationStore.state(for: "gimp")?.progress
        )
        XCTAssertEqual(progress.phase, .performing)
        XCTAssertEqual(progress.inlineLabel, String(localized: "Updating Homebrew…"))
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
            ),
            CaskOperationProgress(
                token: "gimp",
                displayName: "Homebrew",
                action: .updatingHomebrew,
                phase: .performing
            ),
            CaskOperationProgress(token: "mole-app", displayName: "Mole", action: .installing, phase: .connecting)
        ]

        let summary = String(localized: "\(4) operations in progress")
        let downloading = CaskOperationPhase.downloading.label(for: .installing).lowercased()
        let connecting = CaskOperationPhase.connecting.label(for: .installing).lowercased()
        let updating = CaskOperationPhase.performing.label(for: .updating).lowercased()
        let updatingHomebrew = CaskOperationPhase.performing
            .label(for: .updatingHomebrew)
            .lowercased()
        XCTAssertEqual(
            CaskOperationStatus.make(operations: operations, batch: nil)?.message,
            "\(summary) · 1 \(downloading) · 1 \(connecting) · 1 \(updating) · 1 \(updatingHomebrew)"
        )
    }

    func test_operation_status_counts_queued_work_last() {
        let operations = ["a", "b", "c"].map {
            CaskOperationProgress(token: $0, displayName: $0, action: .updating, phase: $0 == "a" ? .downloading : .queued)
        }
        let summary = String(localized: "\(3) operations in progress")
        let downloading = CaskOperationPhase.downloading.label(for: .updating).lowercased()
        let queued = CaskOperationPhase.queued.label(for: .updating).lowercased()

        XCTAssertEqual(
            CaskOperationStatus.make(operations: operations, batch: nil)?.message,
            "\(summary) · 1 \(downloading) · 2 \(queued)"
        )
    }

    func test_batch_status_counts_active_downloads_out_of_the_apps_still_waiting() {
        let phases: [CaskOperationPhase] = [.downloading, .performing, .queued, .verifying]
        let operations = phases.enumerated().map {
            CaskOperationProgress(token: "t\($0.offset)", displayName: "App \($0.offset)", action: .installing, phase: $0.element)
        }
        let batch = CaskBatchProgress(tokens: Set((0 ..< 8).map { "t\($0)" }), finishedCount: 1)
        let status = CaskOperationStatus.make(operations: operations, batch: batch)
        let installing = CaskOperationPhase.performing.label(for: .installing)

        XCTAssertEqual(status?.message, "\(installing) App 1… · \(downloadingCount(2, of: 3))")
        XCTAssertEqual(
            status?.batch?.sentence(bytes: nil) { "Pouring \($0.displayName)…" },
            "Pouring App 1… · \(downloading)… \(count(1, of: 8))"
        )
    }

    func test_batch_status_ignores_finished_and_cancelled_apps() {
        func status(queued: Int, finished: Int) -> String? {
            let phases = Array(repeating: CaskOperationPhase.downloading, count: 3) + Array(repeating: .queued, count: queued)
            let operations = phases.enumerated().map {
                CaskOperationProgress(token: "t\($0.offset)", displayName: "App \($0.offset)", action: .updating, phase: $0.element)
            }
            let batch = CaskBatchProgress(tokens: Set((0 ..< 11).map { "t\($0)" }), finishedCount: finished)
            return CaskOperationStatus.make(operations: operations, batch: batch)?.message
        }

        XCTAssertEqual(status(queued: 7, finished: 1), downloadingCount(3, of: 10))
        XCTAssertEqual(status(queued: 0, finished: 8), downloadingCount(3, of: 3), "cancelling the queue must not raise the count")
    }

    func test_batch_status_names_the_last_app_and_ignores_outside_apps() {
        let operations = [
            CaskOperationProgress(
                token: "t0", displayName: "App 0", action: .updating, phase: .downloading,
                completedBytes: 12_000_000, totalBytes: 34_000_000
            ),
            CaskOperationProgress(token: "other", displayName: "Other", action: .uninstalling, phase: .performing)
        ]
        let batch = CaskBatchProgress(tokens: Set((0 ..< 5).map { "t\($0)" }), finishedCount: 3)
        let status = CaskOperationStatus.make(operations: operations, batch: batch)

        XCTAssertNil(status?.batch?.installing)
        XCTAssertEqual(status?.message, "\(downloading) App 0 · 12 / 34 MB")
        XCTAssertEqual(
            status?.batch?.sentence(bytes: status?.byteProgress) { _ in "" },
            "\(downloading)… 12 / 34 MB \(count(3, of: 5))",
            "the sheet keeps the count last so it stays put at the trailing edge"
        )
    }

    func test_batch_status_counts_the_queue_while_only_an_install_runs() {
        let operations = ["a", "b", "c"].map {
            CaskOperationProgress(token: $0, displayName: $0, action: .updating, phase: $0 == "a" ? .performing : .queued)
        }
        let batch = CaskBatchProgress(tokens: ["a", "b", "c", "d"], finishedCount: 1)
        let updating = CaskOperationPhase.performing.label(for: .updating)
        let queued = CaskOperationPhase.queued.label(for: .updating).lowercased()

        XCTAssertEqual(
            CaskOperationStatus.make(operations: operations, batch: batch)?.message,
            "\(updating) a… · 2 \(queued)"
        )
    }

    private var downloading: String { CaskOperationPhase.downloading.label(for: .installing) }

    private func downloadingCount(_ active: Int, of waiting: Int) -> String {
        String(localized: "Downloading \(active) of \(waiting)")
    }

    private func count(_ finished: Int, of total: Int) -> String {
        String(localized: "(\(finished) of \(total))")
    }

    @MainActor
    func test_status_bar_text_grows_with_text_size_preference() {
        let bar = StatusBarView(caskCount: 3_781, caskFlowRelease: "caskflow-v2026.07.18")
        let standard = NSHostingView(rootView: bar.environment(\.catalogTextScale, 1))
        let larger = NSHostingView(rootView: bar.environment(\.catalogTextScale, 1.2))

        XCTAssertGreaterThan(larger.fittingSize.width, standard.fittingSize.width)
    }

    @MainActor
    func test_progress_capsule_and_status_bar_render() async {
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
        await service.mutationCoordinator.awaitPendingOutput()

        render(CaskActionsView(cask: makeCask("plain")).environment(service), width: 420, height: 400)
        render(CaskActionsView(cask: makeCask("plain"), fullWidth: false).environment(service), width: 420, height: 400)
        render(
            StatusBarView(
                caskCount: 3_781,
                caskFlowRelease: "caskflow-v2026.07.18",
                operation: service.statusBarOperation
            ),
            width: 420, height: 400)
        render(
            ObservedStatusBarView(
                caskCount: 3_781,
                caskFlowRelease: "caskflow-v2026.07.18"
            )
            .environment(service),
            width: 420, height: 400)
    }
}
