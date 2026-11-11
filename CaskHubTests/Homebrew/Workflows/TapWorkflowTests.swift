//
//  TapWorkflowTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/11/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class TapWorkflowTests: XCTestCase {
    func test_add_tap_runs_brew_tap_then_refreshes_index() async throws {
        let sut = makeSUT(indexes: [index(taps: ["saffsanity/sill"], casks: [])])

        try await sut.service.addTap(TapAddRequest(tapName: "saffsanity/sill", remoteURL: nil, caskToken: nil))

        XCTAssertTrue(sut.runner.requests.contains { $0.arguments == ["tap", "saffsanity/sill"] })
        XCTAssertEqual(sut.service.tapIndex.taps.map(\.name), ["saffsanity/sill"])
    }

    func test_add_tap_with_url_passes_url() async throws {
        let sut = makeSUT(indexes: [])
        let request = TapAddRequest(tapName: "user/casks", remoteURL: URL(string: "https://github.com/user/casks"), caskToken: nil)

        try await sut.service.addTap(request)

        XCTAssertTrue(sut.runner.requests.contains {
            $0.arguments == ["tap", "user/casks", "https://github.com/user/casks"]
        })
    }

    func test_remove_tap_with_installed_items_uses_force() async throws {
        let sut = makeSUT(indexes: [])
        updateInstalledCask(tapInstallation("sill", tap: "saffsanity/sill"), in: sut.service)
        sut.formulae = ["saffsanity/sill/sill-cli"]

        let preview = await sut.service.removalPreview(for: "saffsanity/sill")
        XCTAssertEqual(preview.installedCasks.map(\.reference), ["saffsanity/sill/sill"])
        XCTAssertEqual(preview.installedFormulae, ["saffsanity/sill/sill-cli"])

        try await sut.service.removeTap(preview)

        XCTAssertTrue(sut.runner.requests.contains { $0.arguments == ["untap", "--force", "saffsanity/sill"] })
    }

    func test_remove_empty_tap_plain_untap() async throws {
        let sut = makeSUT(indexes: [])

        try await sut.service.removeTap(await sut.service.removalPreview(for: "spotify/public"))

        XCTAssertTrue(sut.runner.requests.contains { $0.arguments == ["untap", "spotify/public"] })
    }

    func test_install_untrusted_tap_cask_waits_for_confirmation() async throws {
        let sut = makeSUT(indexes: [index(taps: ["saffsanity/sill"], casks: ["sill"])])
        await sut.service.refreshTaps()
        let cask = try XCTUnwrap(sut.service.tapIndex.casks.first)

        try await sut.service.installRequestingTrust(cask)

        XCTAssertTrue(sut.runner.requests.isEmpty)
        XCTAssertEqual(sut.service.pendingTrustInstall?.reference, "saffsanity/sill/sill")

        try await sut.service.confirmTrustedInstall(cask)

        XCTAssertNil(sut.service.pendingTrustInstall)
        XCTAssertTrue(sut.runner.requests.contains { $0.arguments.starts(with: ["install", "--cask", "saffsanity/sill/sill"]) })
    }

    func test_cancel_trusted_install_clears_prompt() async throws {
        let sut = makeSUT(indexes: [index(taps: ["saffsanity/sill"], casks: ["sill"])])
        await sut.service.refreshTaps()
        let cask = try XCTUnwrap(sut.service.tapIndex.casks.first)

        try await sut.service.installRequestingTrust(cask)
        sut.service.send(.cancelTrustedInstall)

        XCTAssertNil(sut.service.pendingTrustInstall)
        XCTAssertTrue(sut.runner.requests.isEmpty)
    }

    func test_install_trusted_tap_cask_skips_prompt() async throws {
        let sut = makeSUT(indexes: [index(taps: ["saffsanity/sill"], casks: ["sill"], trustedCasks: ["saffsanity/sill/sill"])])
        await sut.service.refreshTaps()
        let cask = try XCTUnwrap(sut.service.tapIndex.casks.first)

        try await sut.service.installRequestingTrust(cask)

        XCTAssertNil(sut.service.pendingTrustInstall)
        XCTAssertTrue(sut.runner.requests.contains { $0.arguments.starts(with: ["install", "--cask", "saffsanity/sill/sill"]) })
    }

    func test_official_install_never_prompts() async throws {
        let sut = makeSUT(indexes: [])

        try await sut.service.installRequestingTrust(makeCask("figma"))

        XCTAssertNil(sut.service.pendingTrustInstall)
        XCTAssertTrue(sut.runner.requests.contains { $0.arguments.starts(with: ["install", "--cask", "figma"]) })
    }

    func test_update_and_uninstall_never_prompt() async throws {
        let sut = makeSUT(indexes: [index(taps: ["saffsanity/sill"], casks: ["sill"])])
        await sut.service.refreshTaps()
        updateInstalledCask(tapInstallation("sill", tap: "saffsanity/sill"), in: sut.service)

        try await sut.service.upgrade(token: "saffsanity/sill/sill")
        try await sut.service.uninstall(token: "saffsanity/sill/sill")

        XCTAssertNil(sut.service.pendingTrustInstall)
        XCTAssertTrue(sut.runner.requests.contains { $0.arguments.starts(with: ["upgrade", "--cask", "saffsanity/sill/sill"]) })
        XCTAssertTrue(sut.runner.requests.contains { $0.arguments.starts(with: ["uninstall", "--cask", "saffsanity/sill/sill"]) })
    }

    func test_failed_index_load_keeps_previous_index() async {
        let sut = makeSUT(indexes: [index(taps: ["saffsanity/sill"], casks: ["sill"]), nil])

        await sut.service.refreshTaps()
        await sut.service.refreshTaps()

        XCTAssertEqual(sut.service.tapIndex.taps.map(\.name), ["saffsanity/sill"])
    }

    func test_tap_update_skipped_while_operation_running() async {
        let sut = makeSUT(indexes: [])
        sut.service.operationStore.send(.enqueue(.installing), for: "figma")

        await sut.service.updateTapsIfStale(now: .now, maxAge: 0)

        XCTAssertEqual(sut.updateCount, 0)
    }

    func test_tap_update_throttled_by_max_age() async {
        let sut = makeSUT(indexes: [])
        let start = Date()

        await sut.service.updateTapsIfStale(now: start, maxAge: 3600)
        await sut.service.updateTapsIfStale(now: start.addingTimeInterval(60), maxAge: 3600)
        await sut.service.updateTapsIfStale(now: start.addingTimeInterval(3601), maxAge: 3600)

        XCTAssertEqual(sut.updateCount, 2)
    }

    func test_tap_update_refreshes_index_and_outdated() async {
        let sut = makeSUT(indexes: [index(taps: ["saffsanity/sill"], casks: [])])

        await sut.service.updateTapsIfStale(now: .now, maxAge: 0)

        XCTAssertEqual(sut.updateCount, 1)
        XCTAssertEqual(sut.service.tapIndex.taps.map(\.name), ["saffsanity/sill"])
        XCTAssertEqual(sut.outdatedCount, 1)
    }

    // MARK: - Helpers

    private final class SUT {
        let service: LocalHomebrewService
        let runner: StubBrewProcessRunner
        var indexes: [TapIndex?]
        var formulae: [String] = []
        var updateCount = 0
        var outdatedCount = 0

        init(service: LocalHomebrewService, runner: StubBrewProcessRunner, indexes: [TapIndex?]) {
            self.service = service
            self.runner = runner
            self.indexes = indexes
        }
    }

    private func makeSUT(indexes: [TapIndex?]) -> SUT {
        let runner = StubBrewProcessRunner()
        var sut: SUT!
        let service = LocalHomebrewService(defaults: makeScratchDefaults("tap-workflow-\(UUID().uuidString)")) {
            $0.fileManager = NoFilesFileManager()
            $0.processRunner = runner
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
            $0.homebrewOutdatedProvider = {
                sut.outdatedCount += 1
                return HomebrewOutdatedReport(upgradable: [], pinned: [])
            }
            $0.tapIndexProvider = { sut.indexes.isEmpty ? nil : sut.indexes.removeFirst() }
            $0.installedFormulaeProvider = { tap in sut.formulae.filter { $0.hasPrefix("\(tap)/") } }
            $0.tapUpdateProvider = { sut.updateCount += 1 }
        }
        sut = SUT(service: service, runner: runner, indexes: indexes)
        return sut
    }

    private func index(taps: [String], casks: [String], trustedCasks: Set<String> = []) -> TapIndex {
        let summaries = taps.map {
            TapSummary(
                name: $0, remote: nil, official: false, trusted: false,
                caskTokens: casks.map { token in "\(taps[0])/\(token)" }, formulaNames: [], caskFiles: []
            )
        }
        let rows = casks.map { CaskFileTextParser.cask(fromSource: "", token: $0, tap: taps[0]) }
        return TapIndex(taps: summaries, casks: rows, trust: TapTrust(taps: [], casks: trustedCasks))
    }

    private func tapInstallation(_ token: String, tap: String) -> LocalCaskInstallation {
        LocalCaskInstallation(token: token, installedVersion: "1.0", installedAt: nil, appBundleNames: [], tap: tap)
    }
}
