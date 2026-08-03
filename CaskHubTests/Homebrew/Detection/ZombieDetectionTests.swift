//
//  ZombieDetectionTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 20/07/2026.
//

@testable import CaskHub
import XCTest

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
    private func makeEntry(
        _ token: String,
        receiptApps: [String]?,
        caskfile: Bool = true
    ) throws -> URL {
        let versionDir = caskroom.appendingPathComponent("\(token)/1.0")
        try fm.createDirectory(at: versionDir, withIntermediateDirectories: true)
        if let receiptApps {
            let metadata = caskroom.appendingPathComponent("\(token)/.metadata")
            try fm.createDirectory(at: metadata, withIntermediateDirectories: true)
            let receipt: [String: Any] = ["uninstall_artifacts": [["app": receiptApps]]]
            let data = try JSONSerialization.data(withJSONObject: receipt)
            try data.write(to: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
            if caskfile {
                let casks = metadata.appendingPathComponent("1.0/20260101000000.000/Casks")
                try fm.createDirectory(at: casks, withIntermediateDirectories: true)
                try Data("cask \"\(token)\"\n".utf8)
                    .write(to: casks.appendingPathComponent("\(token).rb"))
            }
        }
        return versionDir
    }

    private func scan() -> [String: LocalCaskInstallation] {
        HomebrewInstallationScanner.scanCaskroom(
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

    func test_missing_timestamped_caskfile_is_zombie_even_with_receipt() throws {
        try makeEntry("thorium", receiptApps: ["Thorium.app"], caskfile: false)
        try fm.createDirectory(
            at: appsDir.appendingPathComponent("Thorium.app"), withIntermediateDirectories: true
        )
        XCTAssertEqual(scan()["thorium"]?.isZombie, true)
    }

    func test_latest_timestamp_must_contain_the_matching_caskfile() throws {
        try makeEntry("thorium", receiptApps: ["Thorium.app"])
        let newestCasks = caskroom
            .appendingPathComponent("thorium/.metadata/1.0/20270101000000.000/Casks")
        try fm.createDirectory(at: newestCasks, withIntermediateDirectories: true)
        try Data("cask \"another-token\"\n".utf8)
            .write(to: newestCasks.appendingPathComponent("another-token.rb"))
        try fm.createDirectory(
            at: appsDir.appendingPathComponent("Thorium.app"), withIntermediateDirectories: true
        )

        XCTAssertEqual(scan()["thorium"]?.isZombie, true)
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
        XCTAssertTrue(
            service.operationStore.state(for: "tabby")?.failure?
                .recoveries.contains(.repairAndReinstall) == true
        )

        service.clearError(for: "tabby")
        XCTAssertFalse(
            service.operationStore.state(for: "tabby")?.failure?
                .recoveries.contains(.repairAndReinstall) == true
        )
    }

    @MainActor
    func test_tcc_denial_is_recorded_via_note_failure() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("tcc-note"))
        let error = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "sourcetree", "--adopt"], exitCode: 1,
            stderr: "chmod: /Applications/SourceTree.app: Unable to change file mode: Operation not permitted"
        )
        service.noteFailure(token: "sourcetree", error: error)
        XCTAssertTrue(
            service.operationStore.state(for: "sourcetree")?.failure?
                .recoveries.contains(.openAppManagementSettings) == true
        )
        XCTAssertFalse(
            service.operationStore.state(for: "sourcetree")?.failure?
                .recoveries.contains(.repairAndReinstall) == true
        )
    }

    func test_stranded_app_error_message_explains_repair() {
        let error = LocalHomebrewError.brewCommandFailed(
            args: ["upgrade", "--cask", "tabby"], exitCode: 1,
            stderr: "Error: tabby: It seems there is already an App at "
                + "'/opt/homebrew/Caskroom/tabby/1.0.230/Tabby.app'."
        )
        XCTAssertTrue(error.errorDescription?.contains("Repair") == true)
    }

    func test_stranded_copy_detection_reads_the_filesystem() throws {
        let versionDir = try makeEntry("tabby", receiptApps: ["Tabby.app"])
        XCTAssertFalse(
            HomebrewInstallationScanner.strandedCopyExists(
                in: caskroom,
                token: "tabby",
                fileManager: fm
            ),
            "empty version dir has no stranded copy"
        )

        try fm.createSymbolicLink(
            at: versionDir.appendingPathComponent("Tabby.app"),
            withDestinationURL: appsDir.appendingPathComponent("Tabby.app")
        )
        XCTAssertFalse(
            HomebrewInstallationScanner.strandedCopyExists(
                in: caskroom,
                token: "tabby",
                fileManager: fm
            ),
            "the artifact symlink — dangling or not — is not a stranded copy"
        )

        try fm.createDirectory(
            at: versionDir.appendingPathComponent("Tabby Old.app"), withIntermediateDirectories: true
        )
        XCTAssertTrue(
            HomebrewInstallationScanner.strandedCopyExists(
                in: caskroom,
                token: "tabby",
                fileManager: fm
            )
        )
        XCTAssertFalse(
            HomebrewInstallationScanner.strandedCopyExists(
                in: caskroom,
                token: "other",
                fileManager: fm
            )
        )
    }

    @MainActor
    func test_upgrade_failure_offers_repair_on_filesystem_evidence_alone() throws {
        let versionDir = try makeEntry("tabby", receiptApps: ["Tabby.app"])
        try fm.createDirectory(
            at: versionDir.appendingPathComponent("Tabby.app"), withIntermediateDirectories: true
        )
        let defaults = makeScratchDefaults("stranded-fs")
        defaults.set(root.path, forKey: HomebrewLocator.customPrefixKey)

        let service = LocalHomebrewService(defaults: defaults)
        let rewordedUpgrade = LocalHomebrewError.brewCommandFailed(
            args: ["upgrade", "--cask", "tabby"], exitCode: 1,
            stderr: "some future brew wording our strings don't match"
        )
        service.noteFailure(token: "tabby", error: rewordedUpgrade)
        XCTAssertTrue(
            service.operationStore.state(for: "tabby")?.failure?
                .recoveries.contains(.repairAndReinstall) == true,
            "a parked copy on disk should back up the offer even if brew rewords its error"
        )

        service.clearError(for: "tabby")
        let rewordedInstall = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "tabby"], exitCode: 1,
            stderr: "some future brew wording our strings don't match"
        )
        service.noteFailure(token: "tabby", error: rewordedInstall)
        XCTAssertFalse(
            service.operationStore.state(for: "tabby")?.failure?
                .recoveries.contains(.repairAndReinstall) == true,
            "filesystem evidence only backs upgrade failures"
        )
    }

    /// The Codex→ChatGPT rename: receipt says Codex.app (gone), but the cask's
    /// current artifact ChatGPT.app is alive on disk. Never offer deletion then.
    @MainActor
    func test_zombie_verdict_clears_when_current_cask_app_exists() async throws {
        try makeApplicationBundle(
            in: appsDir, named: "ChatGPT.app", bundleIdentifier: "com.openai.chat"
        )
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("zombie-crosscheck")
        ) {
            $0.applicationDirectories = [appsDir]
        }
        updateInstalledCask(LocalCaskInstallation(
            token: "chatgpt", installedVersion: "26.623", installedAt: nil,
            appBundleNames: ["Codex.app"], isZombie: true
        ), in: service)
        let cask = makeCask("chatgpt", appNames: ["ChatGPT.app"])
        await service.updatePackageCatalog([cask])
        XCTAssertFalse(service.localState(for: cask).isZombie)
    }

    @MainActor
    func test_zombie_verdict_holds_when_current_cask_app_is_gone_too() async {
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("zombie-holds")
        ) {
            $0.applicationDirectories = [appsDir]
        }
        updateInstalledCask(LocalCaskInstallation(
            token: "mole-app", installedVersion: "1.0", installedAt: nil,
            appBundleNames: ["Mole.app"], isZombie: true
        ), in: service)
        let cask = makeCask("mole-app", appNames: ["Mole.app"])
        await service.updatePackageCatalog([cask])
        XCTAssertTrue(service.localState(for: cask).isZombie)
    }

    @MainActor
    func test_zombie_verdict_is_conservative_without_artifact_data() {
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("zombie-no-artifacts")
        ) {
            $0.applicationDirectories = [appsDir]
        }
        updateInstalledCask(LocalCaskInstallation(
            token: "mystery", installedVersion: "1.0", installedAt: nil,
            appBundleNames: ["Mystery.app"], isZombie: true
        ), in: service)
        XCTAssertFalse(
            service.localState(for: makeCask("mystery")).isZombie,
            "no artifact data to verify against → never offer deletion"
        )
    }

    @MainActor
    func test_open_falls_back_to_current_cask_artifact_name() throws {
        try makeApplicationBundle(
            in: appsDir, named: "ChatGPT.app", bundleIdentifier: "com.openai.chat"
        )
        let launcher = RecordingApplicationLauncher()
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("open-fallback")
        ) {
            $0.applicationDirectories = [appsDir]
            $0.applicationLauncher = launcher
        }
        updateInstalledCask(LocalCaskInstallation(
            token: "chatgpt", installedVersion: "26.623", installedAt: nil,
            appBundleNames: ["Codex.app"], isZombie: true
        ), in: service)
        service.open(makeCask("chatgpt", appNames: ["ChatGPT.app"]))
        XCTAssertNil(
            service.operationStore.state(for: "chatgpt")?.failure?.message,
            "stale receipt name should fall back to the cask's current artifact"
        )
        XCTAssertEqual(launcher.lastOpenedURL?.lastPathComponent, "ChatGPT.app")
    }

    @MainActor
    func test_zombies_never_offer_updates() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("zombie-updates"))
        updateInstalledCask(LocalCaskInstallation(
            token: "mole-app", installedVersion: "1.0", installedAt: nil,
            appBundleNames: ["Mole.app"], isZombie: true
        ), in: service)
        XCTAssertFalse(
            service.localState(for: makeCask(
                "mole-app",
                version: "2.0",
                appNames: ["Mole.app"]
            )).hasAvailableUpdate
        )
    }
}
