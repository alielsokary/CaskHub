//
//  AdoptionTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 19/07/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

final class NoFilesFileManager: FileManager {
    override func fileExists(atPath _: String) -> Bool { false }
    override func fileExists(atPath _: String, isDirectory _: UnsafeMutablePointer<ObjCBool>?) -> Bool { false }
}

// MARK: - Adoption error surfaces & scans

final class AdoptionSurfaceTests: XCTestCase {
    func test_error_descriptions_cover_every_case() {
        XCTAssertNotNil(LocalHomebrewError.brewBinaryNotFound.errorDescription)
        XCTAssertTrue(
            LocalHomebrewError.appBundleNotFound(token: "ghost").errorDescription?.contains("ghost") == true
        )

        let mismatch = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "x", "--adopt"], exitCode: 1,
            stderr: "Error: It seems the existing App is different from the one being installed."
        )
        XCTAssertTrue(mismatch.errorDescription?.contains("replace it with Homebrew's copy") == true)

        let checksum = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "x"], exitCode: 1, stderr: "SHA256 mismatch"
        )
        XCTAssertTrue(checksum.errorDescription?.contains("checksum") == true)

        let silent = LocalHomebrewError.brewCommandFailed(args: ["upgrade"], exitCode: 2, stderr: "  ")
        XCTAssertTrue(silent.errorDescription?.contains("exit 2") == true)

        let generic = LocalHomebrewError.brewCommandFailed(args: ["upgrade"], exitCode: 1, stderr: "boom")
        XCTAssertTrue(generic.errorDescription?.contains("boom") == true)
    }

    @MainActor
    func test_open_and_external_lookups_handle_missing_bundles() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("open-missing"))

        service.openApp(token: "ghost")
        XCTAssertNotNil(service.actionErrors["ghost"], "not installed should surface an error")
        service.clearError(for: "ghost")
        XCTAssertNil(service.actionErrors["ghost"])

        service.installedCasks["ghost"] = LocalCaskInstallation(
            token: "ghost", installedVersion: "1", installedAt: nil,
            appBundleNames: ["CaskHubTestNoSuchApp.app"]
        )
        service.openApp(token: "ghost")
        XCTAssertNotNil(service.actionErrors["ghost"], "missing bundle should surface an error")

        let external = makeCask("ghost2", appNames: ["CaskHubTestNoSuchApp.app"])
        service.openExternalApp(cask: external)
        XCTAssertNotNil(service.actionErrors["ghost2"])
        XCTAssertNil(service.externalAppVersion(for: external))
    }

    func test_missing_caskroom_scans_as_no_installed_casks() {
        XCTAssertEqual(LocalHomebrewService.scanCaskroom(fileManager: NoFilesFileManager()).count, 0)
    }

    @MainActor
    func test_refresh_scans_system_and_custom_prefix_round_trips() async {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("refresh-scan"))

        await service.setCustomBrewPrefix("/nonexistent/prefix")
        XCTAssertEqual(service.customBrewPrefix, "/nonexistent/prefix")
        XCTAssertNotNil(service.lastRefresh)

        await service.setCustomBrewPrefix(nil)
        XCTAssertNil(service.customBrewPrefix)
    }

    @MainActor
    func test_adopt_of_unknown_cask_surfaces_brew_error() async throws {
        try XCTSkipUnless(
            LocalHomebrewService.locateBrewBinary() != nil, "needs a Homebrew installation"
        )
        setenv("HOMEBREW_NO_AUTO_UPDATE", "1", 1)

        let service = LocalHomebrewService(defaults: makeScratchDefaults("adopt-e2e"))
        service.permissionProbe = { .granted }
        let token = "caskhub-test-nonexistent-cask"

        try? await service.adopt(token: token)

        XCTAssertNotNil(service.actionErrors[token])
        XCTAssertNil(service.inFlightActions[token])
        XCTAssertTrue(service.permissionRequests.isEmpty)
    }

    func test_permission_probe_completes_without_crashing() {
        let status = AppManagementPermission.probe()
        XCTAssertTrue([.granted, .denied, .unknown].contains(status))
    }

    func test_artifact_stanza_decodes_binary_source_paths() throws {
        let json = Data("""
        [{"app": ["Obsidian.app"]},
         {"binary": ["/Applications/Obsidian.app/Contents/MacOS/obsidian-cli", {"target": "obsidian"}]}]
        """.utf8)
        let stanzas = try JSONDecoder().decode([ArtifactStanza].self, from: json)
        XCTAssertEqual(
            stanzas[1].binarySourcePaths,
            ["/Applications/Obsidian.app/Contents/MacOS/obsidian-cli"]
        )
        XCTAssertEqual(stanzas[1].binaryNames, ["obsidian"])
    }

    @MainActor
    func test_adopt_refuses_when_bundle_lacks_declared_binary() async throws {
        let appsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adopt-preflight-\(UUID().uuidString)")
        let macOSDir = appsDir.appendingPathComponent("Fake.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: appsDir) }

        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("adopt-preflight"),
            applicationDirectories: [appsDir]
        )
        service.permissionProbe = { .granted }
        let cask = makeCask(
            "caskhub-test-nonexistent-cask", appNames: ["Fake.app"],
            binarySourcePaths: ["/Applications/Fake.app/Contents/MacOS/fake-cli"]
        )

        try await service.adopt(cask)

        XCTAssertTrue(service.adoptReplaceOffers.contains(cask.token), "should offer the safe replace path")
        XCTAssertTrue(
            service.actionErrors[cask.token]?.contains("fake-cli") == true,
            "error should name the missing component"
        )
        XCTAssertNil(service.inFlightActions[cask.token], "brew must never run")

        FileManager.default.createFile(
            atPath: macOSDir.appendingPathComponent("fake-cli").path, contents: Data()
        )
        XCTAssertNil(service.adoptBlockedByMissingBinary(cask), "present binary should clear the preflight")
    }

    @MainActor
    func test_adopt_preflight_ignores_binaries_outside_the_bundle() throws {
        let appsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adopt-staged-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: appsDir.appendingPathComponent("Fake.app"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: appsDir) }

        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("adopt-staged"),
            applicationDirectories: [appsDir]
        )
        let cask = makeCask(
            "fake", appNames: ["Fake.app"],
            binarySourcePaths: ["$HOMEBREW_PREFIX/Caskroom/fake/1.0/fake-cli"]
        )
        XCTAssertNil(service.adoptBlockedByMissingBinary(cask))
    }

    func test_artifact_stanza_round_trips_keys_through_codable() throws {
        let stanza = ArtifactStanza(keys: ["app", "zap"], appNames: ["X.app"])
        let data = try JSONEncoder().encode([stanza])
        let decoded = try JSONDecoder().decode([ArtifactStanza].self, from: data)
        XCTAssertEqual(decoded[0].keys, ["app", "zap"])
    }
}
// MARK: - View render smoke tests

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
        service.externalAppNames = ["Chrome.app"]
        service.externalBinaryNames = ["claude"]
        service.installedCasks["managed"] = LocalCaskInstallation(
            token: "managed", installedVersion: "1.0", installedAt: nil, appBundleNames: ["Managed.app"]
        )

        let adoptable = makeCask("chrome", appNames: ["Chrome.app"])
        render(CaskActionsView(cask: adoptable).environment(service).environment(\.isAdoptPage, true))
        render(CaskActionsView(cask: adoptable).environment(service))
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
        service.openApp(token: "chrome")

        render(
            Text("host")
                .caskActionAlerts(for: makeCask("chrome"), showUninstallConfirmation: .constant(false))
                .environment(service)
        )
    }

    @MainActor
    func test_info_popover_renders_external_and_installed_versions() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("render-popover"))
        render(CaskInfoPopover(cask: makeCask("mystery", appNames: ["NoSuchApp.app"])).environment(service))

        service.installedCasks["known"] = LocalCaskInstallation(
            token: "known", installedVersion: "3.1", installedAt: .now, appBundleNames: []
        )
        render(CaskInfoPopover(cask: makeCask("known")).environment(service))
    }
}
