//
//  MutationRecoveryTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 20/07/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class MutationRecoveryTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fileManager.temporaryDirectory
            .appendingPathComponent("mutation-recovery-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: root.appendingPathComponent("Caskroom/zed/1.10.3"),
            withIntermediateDirectories: true
        )
        UserDefaults.standard.set(root.path, forKey: LocalHomebrewService.customBrewPrefixKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: LocalHomebrewService.customBrewPrefixKey)
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func makeService(runner: StubBrewProcessRunner) -> LocalHomebrewService {
        LocalHomebrewService(
            fileManager: fileManager,
            defaults: makeScratchDefaults("repair-recovery"),
            applicationDirectories: [root.appendingPathComponent("Applications")],
            processRunner: runner,
            brewBinaryProvider: { URL(fileURLWithPath: "/test/bin/brew") },
            brewVersionProvider: { "test" }
        )
    }

    func test_repair_reinstalls_when_uninstall_returns_nonzero_after_removing_cask() async throws {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [
            BrewProcessResult(exitCode: 0, output: "fetched"),
            BrewProcessResult(exitCode: 1, output: "Error: cleanup failed\nlibxaw\nlibxmu"),
            BrewProcessResult(exitCode: 0, output: "installed")
        ]
        let caskroomEntry = root.appendingPathComponent("Caskroom/zed")
        runner.onRequest = { [fileManager, caskroomEntry] request in
            if request.arguments.first == "uninstall" {
                try fileManager.removeItem(at: caskroomEntry)
            }
        }

        try await makeService(runner: runner).repairReinstalling(token: "zed")

        XCTAssertEqual(runner.requests.map(\.arguments), [
            ["fetch", "--cask", "zed"],
            ["uninstall", "--cask", "zed", "--force"],
            ["install", "--cask", "zed"]
        ])
    }

    func test_repair_stops_when_failed_uninstall_leaves_caskroom_entry() async {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [
            BrewProcessResult(exitCode: 0, output: "fetched"),
            BrewProcessResult(exitCode: 1, output: "Error: uninstall failed")
        ]

        do {
            try await makeService(runner: runner).repairReinstalling(token: "zed")
            XCTFail("repair must stop while the broken cask entry remains")
        } catch {
            XCTAssertEqual(runner.requests.map(\.arguments), [
                ["fetch", "--cask", "zed"],
                ["uninstall", "--cask", "zed", "--force"]
            ])
        }
    }

    func test_brew_error_diagnostics_keep_error_before_long_cleanup_tail() async {
        let runner = StubBrewProcessRunner()
        let cleanupTail = (1...30).map { "formula-\($0)" }.joined(separator: "\n")
        runner.queuedResults = [BrewProcessResult(
            exitCode: 1,
            output: "Error: the meaningful failure\n" + cleanupTail
        )]

        do {
            try await makeService(runner: runner).install(token: "zed")
            XCTFail("expected failure")
        } catch let LocalHomebrewError.brewCommandFailed(_, _, stderr) {
            XCTAssertTrue(stderr.contains("Error: the meaningful failure"))
            XCTAssertTrue(stderr.contains("formula-30"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
