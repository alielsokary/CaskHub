//
//  SettingsViewTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 16/07/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

@MainActor
private final class BackgroundUpdateCheckerSpy: BackgroundUpdateChecking {
    let automaticallyChecksForUpdates: Bool
    private(set) var checkCount = 0

    init(automaticallyChecksForUpdates: Bool) {
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }

    func checkForUpdatesInBackground() {
        checkCount += 1
    }
}

final class SettingsViewTests: XCTestCase {
    @MainActor
    func test_launch_check_respects_automatic_update_preference() {
        let enabled = BackgroundUpdateCheckerSpy(automaticallyChecksForUpdates: true)
        let disabled = BackgroundUpdateCheckerSpy(automaticallyChecksForUpdates: false)

        UpdaterService.checkForUpdatesOnLaunch(using: enabled)
        UpdaterService.checkForUpdatesOnLaunch(using: disabled)

        XCTAssertEqual(enabled.checkCount, 1)
        XCTAssertEqual(disabled.checkCount, 0)
    }

    @MainActor
    func test_staged_update_not_pending_when_prompt_disabled() {
        var gate = StagedUpdateGate()
        gate.updateStaged(showPromptEnabled: false)

        XCTAssertFalse(gate.pending)
        XCTAssertFalse(gate.consumeResume(canCheck: true))
    }

    @MainActor
    func test_staged_update_resumes_once_after_session_ends() {
        var gate = StagedUpdateGate()
        gate.updateStaged(showPromptEnabled: true)

        XCTAssertTrue(gate.pending)
        // Session still in progress: checkForUpdates() would be a no-op, so hold.
        XCTAssertFalse(gate.consumeResume(canCheck: false))
        // Session ended: resume exactly once.
        XCTAssertTrue(gate.consumeResume(canCheck: true))
        XCTAssertFalse(gate.consumeResume(canCheck: true))
        XCTAssertFalse(gate.pending)
    }

    @MainActor
    func test_no_resume_without_a_staged_update() {
        var gate = StagedUpdateGate()

        XCTAssertFalse(gate.consumeResume(canCheck: true))
    }

    @MainActor
    private func render(_ view: some View) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 480)
        hosting.layoutSubtreeIfNeeded()
    }

    @MainActor
    func test_settings_tabs_render() {
        render(AppearanceSettingsView())
        render(PrivacySettingsView())
        render(AboutSettingsView())
        render(
            GeneralSettingsView()
                .environment(UpdaterService())
                .environment(ImageCacheService())
        )
        render(
            HomebrewSettingsView()
                .environment(LocalHomebrewService())
        )
    }

    @MainActor
    func test_clear_cache_recreates_empty_icon_directory() async {
        let directory = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diskCache = IconDiskCache(directory: directory)
        let cache = ImageCacheService(diskCache: diskCache)

        await cache.clearCache()

        let contents = await diskCache.fileNames()
        XCTAssertTrue(contents.allSatisfy { $0.hasPrefix(".") },
                      "expected no cached icons, found: \(contents)")
    }

    func test_clear_serializes_with_pending_write_and_removes_result() async throws {
        let directory = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diskCache = IconDiskCache(directory: directory)
        let generation = await diskCache.currentGeneration()

        async let stored = diskCache.store(
            Data("icon".utf8),
            token: "pending",
            generation: generation,
            fromCaskFlow: true
        )
        async let cleared: Void = diskCache.clear()
        _ = try await(stored, cleared)

        let data = await diskCache.loadData(token: "pending")
        XCTAssertNil(data)
    }

    func test_write_from_before_clear_is_rejected() async throws {
        let directory = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diskCache = IconDiskCache(directory: directory)
        let staleGeneration = await diskCache.currentGeneration()

        try await diskCache.clear()
        let stored = try await diskCache.store(
            Data("stale".utf8),
            token: "stale",
            generation: staleGeneration,
            fromCaskFlow: true
        )

        XCTAssertFalse(stored)
        let data = await diskCache.loadData(token: "stale")
        XCTAssertNil(data)
    }

    func test_store_recreates_externally_removed_directory() async throws {
        let directory = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diskCache = IconDiskCache(directory: directory)
        let generation = await diskCache.currentGeneration()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: directory)

        let stored = try await diskCache.store(
            Data("icon".utf8),
            token: "recreated",
            generation: generation,
            fromCaskFlow: true
        )

        XCTAssertTrue(stored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor
    func test_theme_preview_assets_are_bundled() {
        for theme in AppTheme.allCases {
            XCTAssertNotNil(theme.previewImage, "missing theme preview for \(theme.rawValue)")
        }
    }

    private func temporaryCacheDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("icon-disk-cache-\(UUID().uuidString)", isDirectory: true)
    }
}
