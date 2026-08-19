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
        XCTAssertEqual(CaskAction.queued.inProgressLabel, String(localized: "Queued…"))
        XCTAssertEqual(CaskAction.queued.identifier, "queued")
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
        {"time": 1700000000, "uninstall_artifacts": [
            {"quit": "com.openai.chat"},
            {"app": ["ChatGPT.app", {"target": "ChatGPT Classic.app"}]},
            {"app": ["Plain.app"]}
        ]}
        """
        let receipt = try InstallReceipt(jsonData: Data(json.utf8))
        XCTAssertEqual(receipt.appBundleNames, ["ChatGPT Classic.app", "Plain.app"])
        XCTAssertEqual(
            receipt.lastUpdatedAt,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @MainActor
    func test_adoptable_requires_on_disk_app_and_no_brew_install() {
        let service = LocalHomebrewService()
        updateInstallationSnapshot(of: service) {
            $0.externalAppNames = ["Google Chrome.app"]
        }

        let chrome = makeCask("google-chrome", appNames: ["Google Chrome.app"])
        XCTAssertTrue(service.localState(for: chrome).isAdoptable)

        updateInstalledCask(installation("google-chrome", version: "1.0"), in: service)
        XCTAssertFalse(service.localState(for: chrome).isAdoptable)

        let firefox = makeCask("firefox", appNames: ["Firefox.app"])
        XCTAssertFalse(service.localState(for: firefox).isAdoptable)

        let cli = makeCask("some-cli")
        XCTAssertFalse(service.localState(for: cli).isAdoptable)
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
        updateInstallationSnapshot(of: service) {
            $0.externalBinaryPaths = ["claude": externalPath]
        }

        let claudeCode = makeCask("claude-code", binaryNames: ["claude"])
        XCTAssertEqual(service.localState(for: claudeCode).externalCLIPath, externalPath)

        updateInstalledCask(installation("claude-code", version: "2.0"), in: service)
        XCTAssertNil(
            service.localState(for: claudeCode).externalCLIPath,
            "brew-installed wins over external detection"
        )

        let other = makeCask("some-tool", binaryNames: ["some-tool"])
        XCTAssertNil(service.localState(for: other).externalCLIPath)
    }

    @MainActor
    func test_uninstall_availability_explains_each_installed_source() {
        let service = LocalHomebrewService()
        let managed = makeCask("managed")
        updateInstalledCask(installation(managed.token, version: "1.0"), in: service)
        XCTAssertEqual(service.localState(for: managed).uninstallAvailability, .available)

        let adoptable = makeCask("adoptable", appNames: ["Adoptable.app"])
        updateInstallationSnapshot(of: service) {
            $0.externalAppNames = ["Adoptable.app"]
        }
        let adoptHint = String(
            localized: "Adopt this app first so CaskHub can manage/uninstall it."
        )
        XCTAssertEqual(
            service.localState(for: adoptable).uninstallAvailability.unavailableReason,
            adoptHint
        )

        let store = makeCask("store", appNames: ["Store.app"])
        updateInstallationSnapshot(of: service) {
            $0.macAppStoreAppNames = ["Store.app"]
        }
        let storeHint = String(
            localized: """
            Installed from the Mac App Store. \
            Uninstall it from Finder or Launchpad.
            """
        )
        XCTAssertEqual(
            service.localState(for: store).uninstallAvailability.unavailableReason,
            storeHint
        )

        let external = makeCask("external", binaryNames: ["external"])
        updateInstallationSnapshot(of: service) {
            $0.externalBinaryPaths = [
                "external": URL(fileURLWithPath: "/usr/local/bin/external")
            ]
        }
        let externalHint = String(
            localized: """
            Installed outside Homebrew at \("/usr/local/bin/external"). \
            Remove or move that file manually before installing \
            the Homebrew version.
            """
        )
        XCTAssertEqual(
            service.localState(for: external).uninstallAvailability.unavailableReason,
            externalHint
        )
        XCTAssertEqual(
            service.localState(for: makeCask("missing")).uninstallAvailability,
            .notApplicable
        )
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

        let appBinary = root.appendingPathComponent("OrbStack.app/Contents/MacOS/xbin/docker")
        try FileManager.default.createDirectory(
            at: appBinary.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: appBinary.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appBinary.path)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("docker"), withDestinationURL: appBinary
        )

        let cellarBinary = root.appendingPathComponent("Cellar/docker/28.0.1/bin/hugo")
        try FileManager.default.createDirectory(
            at: cellarBinary.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: cellarBinary.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cellarBinary.path)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("hugo"), withDestinationURL: cellarBinary
        )

        let scan = HomebrewInstallationScanner.scanBinaryDirectories(
            fileManager: FileManager.default,
            directories: [root]
        )
        XCTAssertEqual(Set(scan.keys), ["copilot"])
        XCTAssertEqual(scan["copilot"]?.lastPathComponent, executable.lastPathComponent)
        XCTAssertNil(scan["stale-tool"], "zero-byte executable artifacts must be ignored")
        XCTAssertNil(
            scan["docker"],
            "a shim into an app bundle belongs to that app, not a standalone CLI"
        )
        XCTAssertNil(
            scan["hugo"],
            "a symlink into the Cellar belongs to a formula, not an external cask install"
        )
    }

    func test_apple_silicon_detection_matches_native_build_arch() {
        #if arch(arm64)
            XCTAssertTrue(HomebrewLocator.isAppleSilicon)
        #endif
        // An x86_64 build can run on either machine (Rosetta), so no assertion there.
    }

    func test_brew_prefix_resolves_from_binary_prefix_and_bin_folder() throws {
        let brew = "/opt/homebrew/bin/brew"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: brew), "needs Homebrew at /opt/homebrew")

        XCTAssertEqual(
            HomebrewLocator.prefix(from: URL(fileURLWithPath: brew)),
            "/opt/homebrew"
        )
        XCTAssertEqual(
            HomebrewLocator.prefix(from: URL(fileURLWithPath: "/opt/homebrew")),
            "/opt/homebrew"
        )
        XCTAssertEqual(
            HomebrewLocator.prefix(from: URL(fileURLWithPath: "/opt/homebrew/bin")),
            "/opt/homebrew"
        )
        XCTAssertNil(
            HomebrewLocator.prefix(from: URL(fileURLWithPath: "/private/tmp"))
        )
    }

    func test_adopt_mismatch_detection() {
        XCTAssertEqual(
            classify(
                ["install", "--cask", "x", "--adopt"],
                "Error: It seems the existing App is different from the one being installed."
            ),
            .adoptVersionMismatch
        )
        XCTAssertEqual(
            classify(
                ["install", "--cask", "x"],
                "It seems there is already an App at '/Applications/X.app'."
            ),
            .appConflict
        )
        XCTAssertEqual(
            classify(
                ["install", "--cask", "x", "--adopt"],
                "curl: (6) Could not resolve host"
            ),
            .networkFailure
        )
    }

    @MainActor
    func test_adopt_preflight_waits_for_app_management_permission() async throws {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("preflight"))
        service.permissionProbe = { .denied }
        let adoptCask = makeCask(
            "chatgpt-classic",
            appNames: ["ChatGPT Classic.app"]
        )
        let replaceCask = makeCask("canva", appNames: ["Canva.app"])
        let adoptApplication = makeDetectedApplication("ChatGPT Classic.app", version: "1.0")
        let replaceApplication = makeDetectedApplication("Canva.app", version: "2.0")
        updateInstallationSnapshot(of: service) {
            $0.externalAppNames = [
                adoptApplication.bundleName,
                replaceApplication.bundleName
            ]
            $0.externalApplicationOwners = [
                adoptCask.token: adoptApplication,
                replaceCask.token: replaceApplication
            ]
        }

        await service.requestAdoption(adoptCask)
        XCTAssertEqual(
            service.operationStore.pendingPermissions["chatgpt-classic"]?.plan.execution,
            .adoptApplication
        )
        XCTAssertNil(
            service.operationStore.state(for: "chatgpt-classic")?.action,
            "brew must not run while permission is missing"
        )

        await service.requestReplacementAdoption(replaceCask)
        XCTAssertEqual(
            service.operationStore.pendingPermissions["canva"]?.plan.execution,
            .replaceApplication,
            "replace path remembers it needs --force"
        )

        // Returning to the app while still denied keeps the requests pending.
        service.resumePendingAdoptions()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(service.operationStore.pendingPermissions.count, 2)

        service.clearError(for: "canva")
        XCTAssertNil(service.operationStore.pendingPermissions["canva"])
    }

    func test_app_management_denial_maps_to_permission_guidance() {
        let stderr = "xattr: [Errno 1] Operation not permitted: '/Applications/ChatGPT Classic.app'"
        XCTAssertEqual(classify(["install", "--cask", "chatgpt-classic"], stderr), .permissionDenied)

        let error = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "chatgpt-classic", "--adopt"], exitCode: 1, stderr: stderr
        )
        XCTAssertTrue(
            error.errorDescription?.contains(String(localized: "App Management")) == true
        )

        let unrelated = "chmod: /opt/homebrew/bin/tool: Operation not permitted"
        XCTAssertEqual(classify([], unrelated), .unknown)
        XCTAssertEqual(
            classify([], "Inspecting /Applications/Example.app\n\(unrelated)"),
            .unknown
        )
        XCTAssertTrue(
            LocalHomebrewError.brewCommandFailed(
                args: ["install", "--cask", "tool"], exitCode: 1, stderr: unrelated
            ).shouldReport
        )
        XCTAssertEqual(classify([], "curl: (6) Could not resolve host"), .networkFailure)
    }

    private func classify(
        _ arguments: [String],
        _ diagnostic: String
    ) -> HomebrewFailureKind {
        HomebrewCommandFailure.classify(
            arguments: arguments,
            exitCode: 1,
            diagnostic: diagnostic
        )
    }

    func test_output_collector_folds_pty_crlf_instead_of_doubling() {
        XCTAssertEqual(BrewOutputCollector.plainText("line one\r\nline two\r\n"), "line one\nline two\n")
        XCTAssertEqual(BrewOutputCollector.plainText("frame\rframe\r"), "frame\nframe\n")
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
        collector.attach(
            to: process,
            readHandle: pipe.fileHandleForReading
        ) { _ in }
        try process.run()

        let start = Date()
        let output = await collector.output()
        XCTAssertTrue(output.contains("hello"))
        XCTAssertFalse(process.isRunning)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "must not wait for the grandchild")
    }

    func test_output_collector_keeps_error_line_through_progress_flood() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "echo 'Error: real failure'; for i in $(seq 1 200); do "
            + "printf 'Extracting  205.4MB/205.4MB⠴ Cask parallels (26.4.0)\\r'; done"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collector = BrewOutputCollector()
        collector.attach(to: process, readHandle: pipe.fileHandleForReading) { _ in }
        try process.run()

        let output = await collector.output()
        XCTAssertTrue(output.contains("Error: real failure"))
        XCTAssertLessThanOrEqual(output.count, 2000)
    }

    func test_output_collector_captures_output_on_normal_exit() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "echo done"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collector = BrewOutputCollector()
        collector.attach(
            to: process,
            readHandle: pipe.fileHandleForReading
        ) { _ in }
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
        let update = Cask.preview(
            token: "google-chrome",
            version: "138.0",
            autoUpdates: true
        )

        XCTAssertFalse(service.localState(for: update).hasAvailableUpdate)

        service.setGreedyUpdates(true)
        XCTAssertTrue(service.localState(for: update).hasAvailableUpdate)
        XCTAssertFalse(
            service.localState(for: Cask.preview(
                token: "google-chrome",
                version: "137.0",
                autoUpdates: true
            )).hasAvailableUpdate,
            "greedy still requires an actual version difference"
        )

        let relaunched = LocalHomebrewService(defaults: defaults)
        XCTAssertTrue(relaunched.greedyUpdates, "greedy preference survives relaunch")
    }

    @MainActor
    func test_adopt_sidebar_filter_lists_only_adoptable_casks() async {
        let homebrew = LocalHomebrewService()
        updateInstallationSnapshot(of: homebrew) {
            $0.externalAppNames = ["Google Chrome.app"]
        }
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
