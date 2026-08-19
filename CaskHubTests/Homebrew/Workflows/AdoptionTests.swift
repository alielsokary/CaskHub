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
    var onRequest: ((Request) throws -> Void)?
    private(set) var requests: [Request] = []

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        onStart _: @escaping (Process) -> Void,
        onChunk _: @escaping @MainActor @Sendable (String) -> Void
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
        return queuedResults.isEmpty
            ? BrewProcessResult(exitCode: 0, output: "")
            : queuedResults.removeFirst()
    }
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
        XCTAssertEqual(
            mismatch.errorDescription,
            String(
                localized: """
                Your installed copy doesn't match the version Homebrew has on \
                record, so it can't be adopted as-is. You can replace it with \
                Homebrew's copy instead — your settings and data are kept.
                """
            )
        )

        let checksum = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "x"], exitCode: 1, stderr: "SHA256 mismatch"
        )
        XCTAssertEqual(
            checksum.errorDescription,
            String(
                localized: """
                The download doesn't match the checksum Homebrew has on record — \
                the developer likely replaced the release file after it was \
                published. This isn't a problem with your Mac; Homebrew refuses \
                mismatched downloads for security. Try again in a day or two once \
                the cask is updated.
                """
            )
        )

        let silent = LocalHomebrewError.brewCommandFailed(args: ["upgrade"], exitCode: 2, stderr: "  ")
        let silentCommand = "brew upgrade"
        let silentExitCode: Int32 = 2
        XCTAssertEqual(
            silent.errorDescription,
            String(localized: "`\(silentCommand)` failed (exit \(silentExitCode)).")
        )

        let generic = LocalHomebrewError.brewCommandFailed(args: ["upgrade"], exitCode: 1, stderr: "boom")
        XCTAssertTrue(generic.errorDescription?.contains("boom") == true)
    }

    func test_cask_conflict_has_actionable_description_and_is_not_reportable() {
        let stderr = "Error: zen-privacy: Cask 'zen-privacy' conflicts with 'zen'."
        let error = LocalHomebrewError.brewCommandFailed(
            args: ["install", "--cask", "zen-privacy"],
            exitCode: 1,
            stderr: stderr
        )

        XCTAssertEqual(LocalHomebrewError.conflictingCask(stderr: stderr), "zen")
        XCTAssertEqual(
            error.errorDescription,
            LocalHomebrewError.caskConflictDescription(
                requestedCask: "zen-privacy",
                installedCask: "zen"
            )
        )
        XCTAssertFalse(error.shouldReport)
    }

    @MainActor
    func test_open_and_external_lookups_handle_missing_bundles() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("open-missing"))

        service.open(makeCask("ghost"))
        XCTAssertNotNil(
            service.operationStore.state(for: "ghost")?.failure?.message,
            "not installed should surface an error"
        )
        service.clearError(for: "ghost")
        XCTAssertNil(service.operationStore.state(for: "ghost")?.failure)

        updateInstalledCask(LocalCaskInstallation(
            token: "ghost", installedVersion: "1", installedAt: nil,
            appBundleNames: ["CaskHubTestNoSuchApp.app"]
        ), in: service)
        service.open(makeCask("ghost"))
        XCTAssertNotNil(
            service.operationStore.state(for: "ghost")?.failure?.message,
            "missing bundle should surface an error"
        )

        let external = makeCask("ghost2", appNames: ["CaskHubTestNoSuchApp.app"])
        service.openExternalApp(cask: external)
        XCTAssertNotNil(service.operationStore.state(for: "ghost2")?.failure?.message)
        XCTAssertNil(service.externalAppVersion(for: external))
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
            guard case let .brewCommandFailed(failure) = error else {
                return XCTFail("unexpected LocalHomebrewError: \(error)")
            }
            XCTAssertEqual(failure.arguments, ["install", "--cask", "firefox"])
            XCTAssertEqual(failure.exitCode, 7)
            XCTAssertEqual(failure.diagnostic, "simulated failure")
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(runner.requests.map(\.arguments), [["install", "--cask", "firefox"]])
        let askpassPath = try? XCTUnwrap(runner.requests.first?.environment["SUDO_ASKPASS"])
        XCTAssertNotNil(runner.requests.first?.askpassContents)
        XCTAssertFalse(askpassPath.map(FileManager.default.fileExists(atPath:)) ?? true)
        XCTAssertNotNil(service.operationStore.state(for: "firefox")?.failure)
        XCTAssertNil(service.operationStore.state(for: "firefox")?.action)
    }

    @MainActor
    func test_install_preflight_blocks_an_installed_conflicting_cask() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner)
        updateInstalledCask(installation("zen", version: "1.21.13b"), in: service)
        let zenPrivacy = makeCask(
            "zen-privacy",
            name: "Zen",
            conflictingCaskTokens: ["zen"]
        )

        try await service.install(zenPrivacy)

        let failure = try XCTUnwrap(service.operationStore.state(for: "zen-privacy")?.failure)
        XCTAssertEqual(failure.kind, .installationPreflight)
        XCTAssertEqual(
            failure.message,
            LocalHomebrewError.caskConflictDescription(
                requestedCask: "zen-privacy",
                installedCask: "zen"
            )
        )
        XCTAssertTrue(runner.requests.isEmpty)
    }

    @MainActor
    func test_install_preflight_allows_a_cask_when_its_conflict_is_not_installed() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner)
        let zenPrivacy = makeCask(
            "zen-privacy",
            conflictingCaskTokens: ["zen"]
        )

        try await service.install(zenPrivacy)

        XCTAssertEqual(
            runner.requests.map(\.arguments),
            [["install", "--cask", "zen-privacy"]]
        )
    }

    @MainActor
    func test_same_version_package_adoption_confirms_then_replaces_cleanly() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner)
        service.permissionProbe = { .granted }
        let cask = makeCask(
            "zoom",
            packageIdentifiers: ["us.zoom.pkg.videomeeting"],
            packageAppNames: ["zoom.us.app"]
        )
        seedExternalInstallation(of: cask, version: "1.0", in: service)

        await service.requestAdoption(cask)
        let request = try XCTUnwrap(
            service.operationStore.state(for: "zoom")?.adoptionRequest
        )
        XCTAssertEqual(request.plan.execution, .replacePackage)

        try await service.confirmAdoption(request)

        XCTAssertEqual(runner.requests.map(\.arguments), [
            ["fetch", "--cask", "zoom"],
            ["uninstall", "--cask", "zoom", "--force"],
            ["install", "--cask", "zoom"]
        ])
        XCTAssertNil(service.operationStore.state(for: "zoom"))
        XCTAssertNil(service.operationStore.state(for: "zoom")?.action)
    }

    @MainActor
    func test_every_planned_adoption_stays_gated_when_permission_is_not_proven() async throws {
        for status in [AppManagementPermission.Status.denied, .unknown] {
            let runner = StubBrewProcessRunner()
            let service = makeMutationService(runner: runner)
            service.permissionProbe = { status }

            let application = makeCask("external-app", appNames: ["External.app"])
            let package = makeCask(
                "package-request",
                packageIdentifiers: ["com.example.package"],
                packageAppNames: ["Package.app"]
            )
            seedExternalInstallation(of: application, version: "1.0", in: service)
            seedExternalInstallation(of: package, version: "2.0", in: service)

            await service.requestAdoption(application)
            await service.requestAdoption(package)

            XCTAssertEqual(Set(service.operationStore.pendingPermissions.keys), [
                "external-app", "package-request"
            ], "\(status) must gate every adoption entry point")
            XCTAssertTrue(runner.requests.isEmpty, "brew must never run before permission is proven")
        }
    }

    @MainActor
    func test_adoption_resumes_at_confirmation_after_permission_is_granted() async {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner)
        service.permissionProbe = { .denied }
        let cask = makeCask("zoom", appNames: ["zoom.us.app"])
        seedExternalInstallation(of: cask, version: "1.0", in: service)

        await service.requestAdoption(cask)
        let pending = service.operationStore.pendingPermissions[cask.token]
        XCTAssertEqual(pending?.cask, cask)

        service.permissionProbe = { .granted }
        service.resumePendingAdoptions()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(
            service.operationStore.state(for: cask.token)?.adoptionRequest,
            pending
        )
        XCTAssertTrue(runner.requests.isEmpty, "granting permission must not skip confirmation")
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
        XCTAssertTrue(
            runner.requests.dropFirst().allSatisfy {
                $0.environment["HOMEBREW_NO_ASK"] == "1"
            },
            "ask-mode prompts EOF on the nulled stdin and abort the run"
        )
    }

    func test_askpass_scripts_are_unique_shell_safe_and_removable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("askpass-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = URL(fileURLWithPath: "/Applications/Cask Hub's.app/Contents/MacOS/CaskHub")

        let firstScript = await AskpassScriptManager.create(
            token: "first; unsafe", directory: directory, executableURL: executable
        )
        let secondScript = await AskpassScriptManager.create(
            token: "second", directory: directory, executableURL: executable
        )
        let first = try XCTUnwrap(firstScript)
        let second = try XCTUnwrap(secondScript)

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.lastPathComponent.hasPrefix("askpass-"))
        let script = try String(contentsOf: first, encoding: .utf8)
        XCTAssertTrue(script.contains("'firstunsafe'"))
        XCTAssertTrue(script.contains("Cask Hub'\"'\"'s.app"))
        let permissions = try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o700)

        await AskpassScriptManager.remove(at: first)
        await AskpassScriptManager.remove(at: second)
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
        let cask = makeCask(token, appNames: ["No Such App.app"])
        seedExternalInstallation(of: cask, version: "1.0", in: service)

        await service.requestAdoption(cask)
        let request = try XCTUnwrap(
            service.operationStore.state(for: token)?.adoptionRequest
        )
        try? await service.confirmAdoption(request)

        XCTAssertNotNil(service.operationStore.state(for: token)?.failure)
        XCTAssertNil(service.operationStore.state(for: token)?.action)
        XCTAssertTrue(service.operationStore.pendingPermissions.isEmpty)
    }

    func test_permission_probe_completes_without_crashing() {
        let status = AppManagementPermission.probe()
        XCTAssertTrue([.granted, .denied, .unknown].contains(status))
    }

    func test_artifact_stanza_decodes_every_bundle_relative_link_source() throws {
        let json = Data("""
        [{"app": ["Obsidian.app"]},
         {"binary": ["/Applications/Obsidian.app/Contents/MacOS/obsidian-cli", {"target": "obsidian"}]},
         {"bash_completion": ["Docker.app/Contents/Resources/etc/docker-compose.bash-completion"]}]
        """.utf8)
        let stanzas = try JSONDecoder().decode([ArtifactStanza].self, from: json)
        XCTAssertEqual(stanzas[1].binaryNames, ["obsidian"])
        XCTAssertEqual(
            stanzas.flatMap(\.adoptionSourcePaths),
            [
                "/Applications/Obsidian.app/Contents/MacOS/obsidian-cli",
                "Docker.app/Contents/Resources/etc/docker-compose.bash-completion"
            ]
        )
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
        seedExternalInstallation(of: cask, version: "1.0", in: service)

        await service.requestAdoption(cask)

        XCTAssertTrue(
            service.operationStore.state(for: cask.token)?.failure?
                .recoveries.contains(.replaceWithHomebrew) == true,
            "should offer the safe replace path"
        )
        XCTAssertTrue(
            service.operationStore.state(for: cask.token)?.failure?
                .message.contains("fake-cli") == true,
            "error should name the missing component"
        )
        XCTAssertNil(service.operationStore.state(for: cask.token)?.action, "brew must never run")

        FileManager.default.createFile(
            atPath: macOSDir.appendingPathComponent("fake-cli").path, contents: Data()
        )
        XCTAssertNil(
            service.adoptBlockedByMissingComponent(cask),
            "present binary should clear the preflight"
        )
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
        XCTAssertNil(service.adoptBlockedByMissingComponent(cask))
    }

}
