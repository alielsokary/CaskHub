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
    override func fileExists(atPath _: String) -> Bool {
        false
    }

    override func fileExists(atPath _: String, isDirectory _: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        false
    }
}

@MainActor
final class StubBrewProcessRunner: BrewProcessRunning {
    struct Request {
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
        let askpassContents: String?
    }

    var queuedResults: [BrewProcessResult] = []
    var queuedChunks: [[String]] = []
    var thrownError: Error?
    var onRequest: ((Request) throws -> Void)?
    private(set) var requests: [Request] = []

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        onStart _: @escaping (Process) -> Void,
        onChunk: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> BrewProcessResult {
        let askpassContents = environment["SUDO_ASKPASS"].flatMap {
            try? String(contentsOfFile: $0, encoding: .utf8)
        }
        let request = Request(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            askpassContents: askpassContents
        )
        requests.append(request)
        try onRequest?(request)
        if let thrownError { throw thrownError }
        if !queuedChunks.isEmpty {
            queuedChunks.removeFirst().forEach(onChunk)
        }
        return queuedResults.isEmpty
            ? BrewProcessResult(exitCode: 0, output: "")
            : queuedResults.removeFirst()
    }
}

// MARK: - Adoption error surfaces & scans

final class AdoptionSurfaceTests: XCTestCase {
    @MainActor
    private func makeMutationService(runner: StubBrewProcessRunner) -> LocalHomebrewService {
        LocalHomebrewService(
            defaults: makeScratchDefaults("mutation-runner-\(UUID().uuidString)")
        ) {
            $0.fileManager = NoFilesFileManager()
            $0.processRunner = runner
            $0.brewBinaryProvider = {
                URL(fileURLWithPath: "/test/bin/brew")
            }
            $0.brewVersionProvider = { "test" }
        }
    }

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
        XCTAssertNotNil(
            service.operationStore.failures["ghost"]?.message,
            "not installed should surface an error"
        )
        service.clearError(for: "ghost")
        XCTAssertNil(service.operationStore.failures["ghost"])

        updateInstalledCask(LocalCaskInstallation(
            token: "ghost", installedVersion: "1", installedAt: nil,
            appBundleNames: ["CaskHubTestNoSuchApp.app"]
        ), in: service)
        service.openApp(token: "ghost")
        XCTAssertNotNil(
            service.operationStore.failures["ghost"]?.message,
            "missing bundle should surface an error"
        )

        let external = makeCask("ghost2", appNames: ["CaskHubTestNoSuchApp.app"])
        service.openExternalApp(cask: external)
        XCTAssertNotNil(service.operationStore.failures["ghost2"]?.message)
        XCTAssertNil(service.externalAppVersion(for: external))
    }

    func test_missing_caskroom_scans_as_no_installed_casks() {
        XCTAssertEqual(
            HomebrewInstallationScanner.scanCaskroom(
                fileManager: NoFilesFileManager()
            ).count,
            0
        )
    }

    @MainActor
    func test_mutations_use_injected_runner_and_map_nonzero_exit() async {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [BrewProcessResult(exitCode: 7, output: "simulated failure")]
        let service = makeMutationService(runner: runner)

        do {
            try await service.install(token: "firefox")
            XCTFail("expected the simulated brew failure")
        } catch let error as LocalHomebrewError {
            guard case let .brewCommandFailed(args, exitCode, stderr) = error else {
                return XCTFail("unexpected LocalHomebrewError: \(error)")
            }
            XCTAssertEqual(args, ["install", "--cask", "firefox"])
            XCTAssertEqual(exitCode, 7)
            XCTAssertEqual(stderr, "simulated failure")
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(runner.requests.map(\.arguments), [["install", "--cask", "firefox"]])
        let askpassPath = try? XCTUnwrap(runner.requests.first?.environment["SUDO_ASKPASS"])
        XCTAssertNotNil(runner.requests.first?.askpassContents)
        XCTAssertFalse(askpassPath.map(FileManager.default.fileExists(atPath:)) ?? true)
        XCTAssertNotNil(service.operationStore.failures["firefox"])
        XCTAssertNil(service.operationStore.state(for: "firefox")?.action)
    }

    @MainActor
    func test_package_adoption_confirms_then_reinstalls_without_adopt_flag() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner)

        service.requestPackageAdoption(token: "zoom")
        XCTAssertTrue(service.operationStore.pendingPackageAdoptions.contains("zoom"))

        try await service.adoptPackage(token: "zoom")

        XCTAssertEqual(runner.requests.map(\.arguments), [["install", "--cask", "zoom"]])
        XCTAssertFalse(service.operationStore.pendingPackageAdoptions.contains("zoom"))
        XCTAssertNil(service.operationStore.state(for: "zoom")?.action)
    }

    @MainActor
    func test_repair_reinstall_runs_fetch_uninstall_and_install_through_runner() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner)

        try await service.repairReinstalling(token: "firefox")

        XCTAssertEqual(runner.requests.map(\.arguments), [
            ["fetch", "--cask", "firefox"],
            ["uninstall", "--cask", "firefox", "--force"],
            ["install", "--cask", "firefox"]
        ])
        XCTAssertTrue(runner.requests.allSatisfy { $0.executableURL.path == "/test/bin/brew" })
        XCTAssertEqual(
            runner.requests[1].environment["HOMEBREW_NO_AUTOREMOVE"], "1",
            "repair must not remove unrelated orphaned formulae"
        )
        XCTAssertNil(runner.requests[0].environment["HOMEBREW_NO_AUTOREMOVE"])
        XCTAssertNil(runner.requests[2].environment["HOMEBREW_NO_AUTOREMOVE"])
    }

    func test_askpass_scripts_are_unique_shell_safe_and_removable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("askpass-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = URL(fileURLWithPath: "/Applications/Cask Hub's.app/Contents/MacOS/CaskHub")

        let first = try XCTUnwrap(AskpassScriptManager.create(
            token: "first; unsafe", directory: directory, executableURL: executable
        ))
        let second = try XCTUnwrap(AskpassScriptManager.create(
            token: "second", directory: directory, executableURL: executable
        ))

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.lastPathComponent.hasPrefix("askpass-"))
        let script = try String(contentsOf: first, encoding: .utf8)
        XCTAssertTrue(script.contains("'firstunsafe'"))
        XCTAssertTrue(script.contains("Cask Hub'\"'\"'s.app"))
        let permissions = try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o700)

        AskpassScriptManager.remove(at: first)
        AskpassScriptManager.remove(at: second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
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
            HomebrewLocator.brewBinaryURL() != nil, "needs a Homebrew installation"
        )
        setenv("HOMEBREW_NO_AUTO_UPDATE", "1", 1)

        let service = LocalHomebrewService(defaults: makeScratchDefaults("adopt-e2e"))
        service.permissionProbe = { .granted }
        let token = "caskhub-test-nonexistent-cask"

        try? await service.adopt(token: token)

        XCTAssertNotNil(service.operationStore.failures[token])
        XCTAssertNil(service.operationStore.state(for: token)?.action)
        XCTAssertTrue(service.operationStore.pendingPermissions.isEmpty)
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
        let app = try makeApplicationBundle(
            in: appsDir, named: "Fake.app", bundleIdentifier: "com.example.fake"
        )
        let macOSDir = app.appendingPathComponent("Contents/MacOS")
        defer { try? FileManager.default.removeItem(at: appsDir) }

        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("adopt-preflight")
        ) {
            $0.applicationDirectories = [appsDir]
        }
        service.permissionProbe = { .granted }
        let cask = makeCask(
            "caskhub-test-nonexistent-cask", appNames: ["Fake.app"],
            binarySourcePaths: ["/Applications/Fake.app/Contents/MacOS/fake-cli"]
        )

        try await service.adopt(cask)

        XCTAssertTrue(
            service.operationStore.tokens(offering: .replaceWithHomebrew).contains(cask.token),
            "should offer the safe replace path"
        )
        XCTAssertTrue(
            service.operationStore.failures[cask.token]?.message.contains("fake-cli") == true,
            "error should name the missing component"
        )
        XCTAssertNil(service.operationStore.state(for: cask.token)?.action, "brew must never run")

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
            defaults: makeScratchDefaults("adopt-staged")
        ) {
            $0.applicationDirectories = [appsDir]
        }
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
