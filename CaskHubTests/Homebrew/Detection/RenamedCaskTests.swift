//
//  RenamedCaskTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 28/11/2026.
//

@testable import CaskHub
import XCTest

final class RenamedCaskTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!
    private var appsDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fileManager.temporaryDirectory.appendingPathComponent("renamed-cask-\(UUID().uuidString)")
        appsDir = root.appendingPathComponent("Applications")
        try fileManager.createDirectory(at: appsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    func test_link_left_by_a_cask_rename_is_not_a_second_install() throws {
        let caskroom = root.appendingPathComponent("Caskroom")
        let metadata = caskroom.appendingPathComponent("chatgpt/.metadata")
        try fileManager.createDirectory(at: caskroom.appendingPathComponent("chatgpt/26.1120"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: metadata, withIntermediateDirectories: true)
        try Data(#"{"uninstall_artifacts":[{"app":["ChatGPT.app"]}]}"#.utf8)
            .write(to: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
        try fileManager.createSymbolicLink(
            atPath: caskroom.appendingPathComponent("codex-app").path, withDestinationPath: "chatgpt"
        )

        let installed = HomebrewInstallationScanner.scanCaskroom(
            at: caskroom, fileManager: fileManager, applicationDirectories: [appsDir]
        )

        XCTAssertEqual(Set(installed.keys), ["chatgpt"])
    }

    @MainActor
    func test_open_finds_an_app_that_renamed_itself_by_bundle_identifier() async throws {
        try makeApplicationBundle(in: appsDir, named: "ChatGPT.app", bundleIdentifier: "com.openai.codex")
        try makeApplicationBundle(in: appsDir, named: "Helper.app", bundleIdentifier: "com.vendor.helper")
        let launcher = RecordingApplicationLauncher()
        let service = LocalHomebrewService(defaults: makeScratchDefaults("open-renamed-\(UUID().uuidString)")) {
            $0.applicationDirectories = [appsDir]
            $0.applicationLauncher = launcher
        }
        let codex = makeCask("codex-app", appNames: ["Codex.app"], applicationBundleIdentifiers: ["com.openai.codex"])
        var hinted = makeCask("vendor-app", appNames: ["Vendor.app"])
        let zap = #"{"zap":[{"trash":"~/Library/Preferences/com.vendor.helper.plist"}]}"#
        hinted.artifacts = [try JSONDecoder().decode(ArtifactStanza.self, from: Data(zap.utf8))] + (hinted.artifacts ?? [])
        await service.updatePackageCatalog([codex, hinted])
        for token in ["codex-app", "vendor-app"] {
            updateInstalledCask(LocalCaskInstallation(
                token: token, installedVersion: "1.0", installedAt: nil, appBundleNames: [], tap: "homebrew/cask"
            ), in: service)
        }

        service.open(codex)
        XCTAssertEqual(launcher.lastOpenedURL?.lastPathComponent, "ChatGPT.app")
        service.open(hinted)
        XCTAssertEqual(launcher.lastOpenedURL?.lastPathComponent, "Helper.app")
        XCTAssertNil(service.operationStore.state(for: "codex-app")?.failure)
    }

    @MainActor
    func test_open_still_fails_when_no_app_carries_the_identifier() async throws {
        let launcher = RecordingApplicationLauncher()
        let service = LocalHomebrewService(defaults: makeScratchDefaults("open-renamed-missing-\(UUID().uuidString)")) {
            $0.applicationDirectories = [appsDir]
            $0.applicationLauncher = launcher
        }
        let codex = makeCask("codex-app", appNames: ["Codex.app"], applicationBundleIdentifiers: ["com.openai.codex"])
        await service.updatePackageCatalog([codex])
        updateInstalledCask(LocalCaskInstallation(
            token: "codex-app", installedVersion: "1.0", installedAt: nil, appBundleNames: ["Codex.app"], tap: "homebrew/cask"
        ), in: service)

        service.open(codex)

        XCTAssertNil(launcher.lastOpenedURL)
        XCTAssertNotNil(service.operationStore.state(for: "codex-app")?.failure)
    }
}
