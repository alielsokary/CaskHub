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

// MARK: - Zombie Caskroom entries

/// A "zombie" is a Caskroom entry whose app was removed outside Homebrew
/// (Pearcleaner, manual trash) or whose install metadata is gone — brew still
/// lists it, but every open/upgrade against it is doomed.
final class ZombieDetectionTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var caskroom: URL!
    private var appsDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fm.temporaryDirectory.appendingPathComponent("zombie-\(UUID().uuidString)")
        caskroom = root.appendingPathComponent("Caskroom")
        appsDir = root.appendingPathComponent("Applications")
        try fm.createDirectory(at: caskroom, withIntermediateDirectories: true)
        try fm.createDirectory(at: appsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// receiptApps nil = no INSTALL_RECEIPT.json at all.
    @discardableResult
    private func makeEntry(_ token: String, receiptApps: [String]?) throws -> URL {
        let versionDir = caskroom.appendingPathComponent("\(token)/1.0")
        try fm.createDirectory(at: versionDir, withIntermediateDirectories: true)
        if let receiptApps {
            let metadata = caskroom.appendingPathComponent("\(token)/.metadata")
            try fm.createDirectory(at: metadata, withIntermediateDirectories: true)
            let receipt: [String: Any] = ["uninstall_artifacts": [["app": receiptApps]]]
            let data = try JSONSerialization.data(withJSONObject: receipt)
            try data.write(to: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
        }
        return versionDir
    }

    private func scan() -> [String: LocalCaskInstallation] {
        LocalHomebrewService.scanCaskroom(
            at: caskroom, fileManager: fm, applicationDirectories: [appsDir]
        )
    }

    func test_missing_app_with_dangling_symlink_is_zombie() throws {
        let versionDir = try makeEntry("mole-app", receiptApps: ["Mole.app"])
        try fm.createSymbolicLink(
            at: versionDir.appendingPathComponent("Mole.app"),
            withDestinationURL: appsDir.appendingPathComponent("Mole.app")
        )
        XCTAssertEqual(scan()["mole-app"]?.isZombie, true)
    }

    func test_app_present_in_applications_is_not_zombie() throws {
        try makeEntry("chrome", receiptApps: ["Chrome.app"])
        try fm.createDirectory(
            at: appsDir.appendingPathComponent("Chrome.app"), withIntermediateDirectories: true
        )
        XCTAssertEqual(scan()["chrome"]?.isZombie, false)
    }

    func test_real_app_parked_inside_caskroom_is_not_zombie() throws {
        let versionDir = try makeEntry("tabby", receiptApps: ["Tabby.app"])
        try fm.createDirectory(
            at: versionDir.appendingPathComponent("Tabby.app"), withIntermediateDirectories: true
        )
        XCTAssertEqual(scan()["tabby"]?.isZombie, false)
    }

    func test_missing_receipt_is_zombie() throws {
        try makeEntry("sequel-ace", receiptApps: nil)
        XCTAssertEqual(scan()["sequel-ace"]?.isZombie, true)
    }

    func test_cli_cask_with_appless_receipt_is_not_zombie() throws {
        try makeEntry("some-cli", receiptApps: [])
        XCTAssertEqual(scan()["some-cli"]?.isZombie, false)
    }

    @MainActor
    func test_stranded_app_failure_offers_repair_and_clear_removes_it() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("stranded-offer"))
        let error = LocalHomebrewError.brewCommandFailed(
            args: ["upgrade", "--cask", "tabby"], exitCode: 1,
            stderr: "Error: tabby: It seems there is already an App at "
                + "'/opt/homebrew/Caskroom/tabby/1.0.230/Tabby.app'."
        )
        service.noteFailure(token: "tabby", error: error)
        XCTAssertTrue(service.repairOffers.contains("tabby"))

        service.clearError(for: "tabby")
        XCTAssertFalse(service.repairOffers.contains("tabby"))
    }

    @MainActor
    func test_tcc_denial_is_recorded_via_note_failure() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("tcc-note"))
        let error = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "sourcetree", "--adopt"], exitCode: 1,
            stderr: "chmod: Unable to change file mode: Operation not permitted"
        )
        service.noteFailure(token: "sourcetree", error: error)
        XCTAssertTrue(service.appManagementDenials.contains("sourcetree"))
        XCTAssertFalse(service.repairOffers.contains("sourcetree"))
    }

    func test_stranded_app_error_message_explains_repair() {
        let error = LocalHomebrewError.brewCommandFailed(
            args: ["upgrade", "--cask", "tabby"], exitCode: 1,
            stderr: "Error: tabby: It seems there is already an App at "
                + "'/opt/homebrew/Caskroom/tabby/1.0.230/Tabby.app'."
        )
        XCTAssertTrue(error.errorDescription?.contains("Repair") == true)
    }

    /// The Codex→ChatGPT rename: receipt says Codex.app (gone), but the cask's
    /// current artifact ChatGPT.app is alive on disk. Never offer deletion then.
    @MainActor
    func test_zombie_verdict_clears_when_current_cask_app_exists() throws {
        try fm.createDirectory(
            at: appsDir.appendingPathComponent("ChatGPT.app"), withIntermediateDirectories: true
        )
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("zombie-crosscheck"),
            applicationDirectories: [appsDir]
        )
        service.installedCasks["chatgpt"] = LocalCaskInstallation(
            token: "chatgpt", installedVersion: "26.623", installedAt: nil,
            appBundleNames: ["Codex.app"], isZombie: true
        )
        XCTAssertFalse(service.isZombie(makeCask("chatgpt", appNames: ["ChatGPT.app"])))
    }

    @MainActor
    func test_zombie_verdict_holds_when_current_cask_app_is_gone_too() {
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("zombie-holds"),
            applicationDirectories: [appsDir]
        )
        service.installedCasks["mole-app"] = LocalCaskInstallation(
            token: "mole-app", installedVersion: "1.0", installedAt: nil,
            appBundleNames: ["Mole.app"], isZombie: true
        )
        XCTAssertTrue(service.isZombie(makeCask("mole-app", appNames: ["Mole.app"])))
    }

    @MainActor
    func test_zombie_verdict_is_conservative_without_artifact_data() {
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("zombie-no-artifacts"),
            applicationDirectories: [appsDir]
        )
        service.installedCasks["mystery"] = LocalCaskInstallation(
            token: "mystery", installedVersion: "1.0", installedAt: nil,
            appBundleNames: ["Mystery.app"], isZombie: true
        )
        XCTAssertFalse(
            service.isZombie(makeCask("mystery")),
            "no artifact data to verify against → never offer deletion"
        )
    }

    @MainActor
    func test_open_falls_back_to_current_cask_artifact_name() throws {
        try fm.createDirectory(
            at: appsDir.appendingPathComponent("ChatGPT.app"), withIntermediateDirectories: true
        )
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("open-fallback"),
            applicationDirectories: [appsDir]
        )
        service.installedCasks["chatgpt"] = LocalCaskInstallation(
            token: "chatgpt", installedVersion: "26.623", installedAt: nil,
            appBundleNames: ["Codex.app"], isZombie: true
        )
        service.open(makeCask("chatgpt", appNames: ["ChatGPT.app"]))
        XCTAssertNil(
            service.actionErrors["chatgpt"],
            "stale receipt name should fall back to the cask's current artifact"
        )
    }

    @MainActor
    func test_zombies_never_offer_updates() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("zombie-updates"))
        service.installedCasks["mole-app"] = LocalCaskInstallation(
            token: "mole-app", installedVersion: "1.0", installedAt: nil,
            appBundleNames: ["Mole.app"], isZombie: true
        )
        XCTAssertFalse(
            service.hasAvailableUpdate(token: "mole-app", remoteVersion: "2.0", autoUpdates: nil)
        )
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
