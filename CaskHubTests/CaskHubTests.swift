//
//  CaskHubTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 08/02/2026.
//

@testable import CaskHub
import XCTest

final class CaskHubTests: XCTestCase {
    @MainActor
    func test_display_version_strips_packaging_suffixes() {
        XCTAssertEqual(makeCask("test", version: "125.0").displayVersion, "125.0")
        XCTAssertEqual(makeCask("test", version: "125.0,build42").displayVersion, "125.0")
        XCTAssertEqual(makeCask("test", version: "125.0_1").displayVersion, "125.0")
        XCTAssertEqual(makeCask("test", version: "1.2.3-beta").displayVersion, "1.2.3")
        XCTAssertEqual(makeCask("test", version: "2024.10.13").displayVersion, "2024.10.13")
        XCTAssertEqual(makeCask("test", version: "beta").displayVersion, "beta")
    }

    @MainActor
    func test_meta_line_omits_unknown_downloads() {
        XCTAssertEqual(makeCask("test", version: "125.0").metaLine(downloads: "1.2M"), "↓ 1.2M · v125.0")
        XCTAssertEqual(makeCask("test", version: "125.0").metaLine(downloads: nil), "v125.0")
    }

    @MainActor
    func test_update_all_with_empty_queue_clears_flag() async {
        let local = LocalHomebrewService()
        await local.updateAll(tokens: [])
        XCTAssertFalse(local.isUpdatingAll)
    }

    @MainActor
    func test_queued_action_labels_as_queued() {
        XCTAssertEqual(CaskAction.queued.inProgressLabel, "Queued…")
    }

    // MARK: - Adoption

    func test_artifact_stanza_decodes_app_names_and_rename_targets() throws {
        let json = """
        [
            {"app": ["Google Chrome.app"], "target": "/Applications/Google Chrome.app"},
            {"zap": [{"trash": ["~/Library/Caches/x"]}]},
            {"app": ["ChatGPT.app", {"target": "ChatGPT Classic.app"}]}
        ]
        """
        let stanzas = try JSONDecoder().decode([ArtifactStanza].self, from: Data(json.utf8))
        XCTAssertEqual(stanzas[0].appNames, ["Google Chrome.app"])
        XCTAssertEqual(stanzas[1].appNames, [])
        XCTAssertEqual(
            stanzas[2].appNames, ["ChatGPT Classic.app"],
            "a rename target is the bundle that actually lands on disk"
        )
    }

    func test_install_receipt_resolves_renamed_app_bundles() throws {
        let json = """
        {"uninstall_artifacts": [
            {"quit": "com.openai.chat"},
            {"app": ["ChatGPT.app", {"target": "ChatGPT Classic.app"}]},
            {"app": ["Plain.app"]}
        ]}
        """
        let receipt = try InstallReceipt(jsonData: Data(json.utf8))
        XCTAssertEqual(receipt.appBundleNames, ["ChatGPT Classic.app", "Plain.app"])
    }

    @MainActor
    func test_adoptable_requires_on_disk_app_and_no_brew_install() {
        let service = LocalHomebrewService()
        updateInstallationSnapshot(of: service, externalAppNames: ["Google Chrome.app"])

        let chrome = makeCask("google-chrome", appNames: ["Google Chrome.app"])
        XCTAssertTrue(service.isAdoptable(chrome))

        updateInstalledCask(installation("google-chrome", version: "1.0"), in: service)
        XCTAssertFalse(service.isAdoptable(chrome))

        let firefox = makeCask("firefox", appNames: ["Firefox.app"])
        XCTAssertFalse(service.isAdoptable(firefox))

        let cli = makeCask("some-cli")
        XCTAssertFalse(service.isAdoptable(cli))
    }

    func test_artifact_stanza_decodes_binary_names_from_paths() throws {
        let json = """
        [{"binary": ["claude"], "target": "/opt/homebrew/bin/claude"},
         {"binary": ["staged/bin/tool", {"target": "tool-renamed"}]}]
        """
        let stanzas = try JSONDecoder().decode([ArtifactStanza].self, from: Data(json.utf8))
        XCTAssertEqual(stanzas[0].binaryNames, ["claude"])
        XCTAssertEqual(stanzas[1].binaryNames, ["tool-renamed"])
    }

    @MainActor
    func test_external_cli_detection_requires_binary_on_disk_and_no_brew_install() {
        let service = LocalHomebrewService()
        let externalPath = URL(fileURLWithPath: "/usr/local/bin/claude")
        updateInstallationSnapshot(of: service, externalBinaryPaths: ["claude": externalPath])

        let claudeCode = makeCask("claude-code", binaryNames: ["claude"])
        XCTAssertEqual(service.externalCLIPath(claudeCode), externalPath)

        updateInstalledCask(installation("claude-code", version: "2.0"), in: service)
        XCTAssertNil(service.externalCLIPath(claudeCode), "brew-installed wins over external detection")

        let other = makeCask("some-tool", binaryNames: ["some-tool"])
        XCTAssertNil(service.externalCLIPath(other))
    }

    @MainActor
    func test_uninstall_availability_explains_each_installed_source() {
        let service = LocalHomebrewService()
        let managed = makeCask("managed")
        updateInstalledCask(installation(managed.token, version: "1.0"), in: service)
        XCTAssertEqual(service.uninstallAvailability(for: managed), .available)

        let adoptable = makeCask("adoptable", appNames: ["Adoptable.app"])
        updateInstallationSnapshot(of: service, externalAppNames: ["Adoptable.app"])
        let adoptHint = "Adopt this app first so CaskHub can manage/uninstall it."
        XCTAssertEqual(service.uninstallAvailability(for: adoptable).unavailableReason, adoptHint)

        let store = makeCask("store", appNames: ["Store.app"])
        updateInstallationSnapshot(of: service, macAppStoreAppNames: ["Store.app"])
        let storeHint = "Installed from the Mac App Store. Uninstall it from Finder or Launchpad."
        XCTAssertEqual(service.uninstallAvailability(for: store).unavailableReason, storeHint)

        let external = makeCask("external", binaryNames: ["external"])
        updateInstallationSnapshot(
            of: service,
            externalBinaryPaths: ["external": URL(fileURLWithPath: "/usr/local/bin/external")]
        )
        let externalHint = "Installed outside Homebrew at /usr/local/bin/external. "
            + "Remove or move that file manually before installing the Homebrew version."
        XCTAssertEqual(service.uninstallAvailability(for: external).unavailableReason, externalHint)
        XCTAssertEqual(service.uninstallAvailability(for: makeCask("missing")), .notApplicable)
    }

    func test_binary_scan_detects_executables_in_homebrew_prefix() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let executable = root.appendingPathComponent("copilot")
        FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8))
        let emptyExecutable = root.appendingPathComponent("stale-tool")
        FileManager.default.createFile(atPath: emptyExecutable.path, contents: Data())
        for path in [executable.path, emptyExecutable.path] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }

        let scan = LocalHomebrewService.scanBinaryDirectories(
            fileManager: FileManager.default,
            directories: [root]
        )
        XCTAssertEqual(Set(scan.keys), ["copilot"])
        XCTAssertEqual(scan["copilot"]?.lastPathComponent, executable.lastPathComponent)
        XCTAssertNil(scan["stale-tool"], "zero-byte executable artifacts must be ignored")
    }

    func test_apple_silicon_detection_matches_native_build_arch() {
        #if arch(arm64)
            XCTAssertTrue(LocalHomebrewService.isAppleSilicon)
        #endif
        // An x86_64 build can run on either machine (Rosetta), so no assertion there.
    }

    func test_brew_prefix_resolves_from_binary_prefix_and_bin_folder() throws {
        let brew = "/opt/homebrew/bin/brew"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: brew), "needs Homebrew at /opt/homebrew")

        XCTAssertEqual(
            LocalHomebrewService.brewPrefix(fromSelection: URL(fileURLWithPath: brew)), "/opt/homebrew"
        )
        XCTAssertEqual(
            LocalHomebrewService.brewPrefix(fromSelection: URL(fileURLWithPath: "/opt/homebrew")), "/opt/homebrew"
        )
        XCTAssertEqual(
            LocalHomebrewService.brewPrefix(fromSelection: URL(fileURLWithPath: "/opt/homebrew/bin")), "/opt/homebrew"
        )
        XCTAssertNil(LocalHomebrewService.brewPrefix(fromSelection: URL(fileURLWithPath: "/private/tmp")))
    }

    func test_adopt_mismatch_detection() {
        XCTAssertTrue(LocalHomebrewError.isAdoptMismatch(
            args: ["install", "--cask", "x", "--adopt"],
            stderr: "Error: It seems the existing App is different from the one being installed."
        ))
        XCTAssertFalse(LocalHomebrewError.isAdoptMismatch(
            args: ["install", "--cask", "x"],
            stderr: "It seems there is already an App at '/Applications/X.app'."
        ))
        XCTAssertFalse(LocalHomebrewError.isAdoptMismatch(
            args: ["install", "--cask", "x", "--adopt"],
            stderr: "curl: (6) Could not resolve host"
        ))
    }

    @MainActor
    func test_adopt_preflight_waits_for_app_management_permission() async throws {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("preflight"))
        service.permissionProbe = { .denied }

        try await service.adopt(token: "chatgpt-classic")
        XCTAssertEqual(service.operationStore.pendingPermissions["chatgpt-classic"], false)
        XCTAssertNil(
            service.operationStore.state(for: "chatgpt-classic")?.action,
            "brew must not run while permission is missing"
        )

        try await service.adoptReplacing(token: "canva")
        XCTAssertEqual(
            service.operationStore.pendingPermissions["canva"],
            true,
            "replace path remembers it needs --force"
        )

        // Returning to the app while still denied keeps the requests pending.
        service.resumePendingAdoptions()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(service.operationStore.pendingPermissions.count, 2)

        service.cancelPermissionRequest(token: "canva")
        XCTAssertNil(service.operationStore.pendingPermissions["canva"])
    }

    func test_app_management_denial_maps_to_permission_guidance() {
        let stderr = "xattr: [Errno 1] Operation not permitted: '/Applications/ChatGPT Classic.app'"
        XCTAssertTrue(LocalHomebrewError.isAppManagementDenial(stderr: stderr))

        let error = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "chatgpt-classic", "--adopt"], exitCode: 1, stderr: stderr
        )
        XCTAssertTrue(error.errorDescription?.contains("App Management") == true)

        let unrelated = "chmod: /opt/homebrew/bin/tool: Operation not permitted"
        XCTAssertFalse(LocalHomebrewError.isAppManagementDenial(stderr: unrelated))
        XCTAssertFalse(
            LocalHomebrewError.isAppManagementDenial(
                stderr: "Inspecting /Applications/Example.app\n\(unrelated)"
            )
        )
        XCTAssertEqual(LocalHomebrewError.failureClass(stderr: unrelated), "uncategorized")
        XCTAssertTrue(
            LocalHomebrewError.brewCommandFailed(
                args: ["install", "--cask", "tool"], exitCode: 1, stderr: unrelated
            ).shouldReport
        )
        XCTAssertFalse(LocalHomebrewError.isAppManagementDenial(stderr: "curl: (6) Could not resolve host"))
    }

    func test_output_collector_finishes_when_grandchild_keeps_pipe_open() async throws {
        // Reproduces the stuck adopt spinner: sh exits but its backgrounded child
        // inherits the pipe's write end, so EOF never arrives.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "echo hello; sleep 30 & exit 0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collector = BrewOutputCollector()
        collector.attach(to: process, pipe: pipe) { _ in }
        try process.run()

        let start = Date()
        let output = await collector.output()
        XCTAssertTrue(output.contains("hello"))
        XCTAssertFalse(process.isRunning)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "must not wait for the grandchild")
    }

    func test_output_collector_captures_output_on_normal_exit() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "echo done"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collector = BrewOutputCollector()
        collector.attach(to: process, pipe: pipe) { _ in }
        try process.run()

        let output = await collector.output()
        XCTAssertTrue(output.contains("done"))
        XCTAssertEqual(process.terminationStatus, 0)
    }

    @MainActor
    func test_greedy_updates_include_auto_updating_casks_and_persist() {
        let defaults = makeScratchDefaults("greedy")
        let service = LocalHomebrewService(defaults: defaults)
        updateInstalledCask(installation("google-chrome", version: "137.0"), in: service)

        XCTAssertFalse(service.hasAvailableUpdate(
            token: "google-chrome", remoteVersion: "138.0", autoUpdates: true
        ))

        service.setGreedyUpdates(true)
        XCTAssertTrue(service.hasAvailableUpdate(
            token: "google-chrome", remoteVersion: "138.0", autoUpdates: true
        ))
        XCTAssertFalse(service.hasAvailableUpdate(
            token: "google-chrome", remoteVersion: "137.0", autoUpdates: true
        ), "greedy still requires an actual version difference")

        let relaunched = LocalHomebrewService(defaults: defaults)
        XCTAssertTrue(relaunched.greedyUpdates, "greedy preference survives relaunch")
    }

    @MainActor
    func test_adopt_sidebar_filter_lists_only_adoptable_casks() async {
        let homebrew = LocalHomebrewService()
        updateInstallationSnapshot(of: homebrew, externalAppNames: ["Google Chrome.app"])
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("google-chrome", appNames: ["Google Chrome.app"]),
                makeCask("slack", appNames: ["Slack.app"])
            ],
            localHomebrew: homebrew
        )
        vm.selectedSidebar = .library(.adopt)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["google-chrome"])
    }
}
