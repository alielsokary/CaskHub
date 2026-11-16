//
//  ForceUpgradeRecoveryTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 16/11/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class ForceUpgradeRecoveryTests: XCTestCase {
    func test_update_blocked_by_vanished_app_recovers_with_forced_upgrade() async throws {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [
            .success,
            BrewProcessResult(exitCode: 1, output: "==> Upgrading chatgpt\n"
                + "Error: chatgpt: It seems the App source '/Applications/Codex.app' is not there."),
            .success,
            .success
        ]
        let defaults = makeScratchDefaults("force-upgrade-\(UUID().uuidString)")
        let service = LocalHomebrewService(defaults: defaults) {
            $0.processRunner = runner
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
        }

        try? await service.upgrade(token: "chatgpt")
        XCTAssertEqual(service.operationStore.state(for: "chatgpt")?.failure?.recoveries, [.forceUpgrade])

        service.send(.forceUpgrade(token: "chatgpt"))
        let forced = ["upgrade", "--cask", "chatgpt", "--force"]
        let ran = expectation(for: NSPredicate { _, _ in
            MainActor.assumeIsolated { runner.requests.count == 4 }
        }, evaluatedWith: nil)
        await fulfillment(of: [ran], timeout: 3)
        XCTAssertEqual(runner.requests.map(\.arguments).suffix(2), [["fetch", "--cask", "chatgpt"], forced])
    }
}
