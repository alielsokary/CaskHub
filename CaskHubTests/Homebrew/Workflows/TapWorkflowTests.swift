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
        let sut = makeSUT(indexes: [makeTapIndex(["saffsanity/sill": []])])

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
        let (sut, cask) = try await loadedSillTap()

        try await sut.service.installRequestingTrust(cask)

        XCTAssertTrue(sut.runner.requests.isEmpty)
        XCTAssertEqual(sut.service.pendingTrustInstall?.reference, "saffsanity/sill/sill")

        try await sut.service.confirmTrustedInstall(cask)

        XCTAssertNil(sut.service.pendingTrustInstall)
        XCTAssertTrue(sut.runner.requests.contains { $0.arguments.starts(with: ["install", "--cask", "saffsanity/sill/sill"]) })
    }

    func test_cancel_trusted_install_clears_prompt() async throws {
        let (sut, cask) = try await loadedSillTap()

        try await sut.service.installRequestingTrust(cask)
        sut.service.send(.cancelTrustedInstall)

        XCTAssertNil(sut.service.pendingTrustInstall)
        XCTAssertTrue(sut.runner.requests.isEmpty)
    }

    func test_install_trusted_tap_cask_skips_prompt() async throws {
        let (sut, cask) = try await loadedSillTap(trusted: true)
        sut.trust = TapTrust(taps: [], casks: ["saffsanity/sill/sill"])

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

    func test_brew_refusing_an_untrusted_tap_on_uninstall_offers_trust_and_uninstall() {
        let refusal = "Error: Refusing to load cask lab421/tap/forel from untrusted tap lab421/tap.\n"
            + "Run `brew trust --cask lab421/tap/forel` or `brew trust lab421/tap` to trust it."
        func failure(_ arguments: [String]) -> CaskOperationFailure {
            CaskOperationFailureFactory.make(
                from: LocalHomebrewError.brewCommandFailed(args: arguments, exitCode: 1, stderr: refusal),
                strandedCopyExists: false
            )
        }

        let kind = HomebrewCommandFailure(arguments: ["uninstall"], exitCode: 1, diagnostic: refusal).kind
        XCTAssertEqual(kind.issueType, "Homebrew.UntrustedTap")
        XCTAssertEqual(failure(["uninstall", "--cask", "lab421/tap/forel"]).recoveries, [.trustAndUninstall])
        XCTAssertEqual(failure(["uninstall", "--cask", "lab421/tap/forel", "--zap"]).recoveries, [.trustAndUninstallRemovingData])
        XCTAssertEqual(failure(["upgrade", "--cask", "lab421/tap/forel"]).recoveries, [])
        XCTAssertFalse(failure(["uninstall", "--cask", "lab421/tap/forel"]).message.contains("Refusing"))
    }

    func test_trust_and_uninstall_trusts_the_cask_before_uninstalling() async throws {
        let sut = makeSUT(indexes: [])

        try await sut.service.trustAndUninstall(token: "lab421/tap/forel", removingData: true)

        let commands = sut.runner.requests.map(\.arguments).filter { ["trust", "uninstall"].contains($0.first) }
        XCTAssertEqual(commands, [
            ["trust", "--cask", "lab421/tap/forel"],
            sut.service.uninstallArguments(token: "lab421/tap/forel", removingData: true)
        ])
    }

    func test_update_and_uninstall_never_prompt() async throws {
        let sut = makeSUT(indexes: [makeTapIndex(["saffsanity/sill": ["sill"]])])
        await sut.service.refreshTaps()
        updateInstalledCask(tapInstallation("sill", tap: "saffsanity/sill"), in: sut.service)

        try await sut.service.upgrade(token: "saffsanity/sill/sill")
        try await sut.service.uninstall(token: "saffsanity/sill/sill")

        XCTAssertNil(sut.service.pendingTrustInstall)
        XCTAssertTrue(sut.runner.requests.contains { $0.arguments.starts(with: ["upgrade", "--cask", "saffsanity/sill/sill"]) })
        XCTAssertTrue(sut.runner.requests.contains { $0.arguments.starts(with: ["uninstall", "--cask", "saffsanity/sill/sill"]) })
    }

    func test_failed_index_load_keeps_previous_index() async {
        let sut = makeSUT(indexes: [makeTapIndex(["saffsanity/sill": ["sill"]]), nil])

        await sut.service.refreshTaps()
        await sut.service.refreshTaps()

        XCTAssertEqual(sut.service.tapIndex.taps.map(\.name), ["saffsanity/sill"])
    }

    func test_tap_update_skipped_while_operation_running() async {
        let sut = makeSUT(indexes: [])
        sut.service.tapIndex = makeTapIndex(["saffsanity/sill": []])
        sut.service.operationStore.send(.enqueue(.installing), for: "figma")

        await sut.service.updateTapsIfStale(now: .now, maxAge: 0)

        XCTAssertEqual(sut.updateCount, 0)
    }

    func test_tap_update_skipped_without_third_party_taps() async {
        let sut = makeSUT(indexes: [])

        await sut.service.updateTapsIfStale(now: .now, maxAge: 0)

        XCTAssertEqual(sut.updateCount, 0, "brew update also updates Homebrew itself")
    }

    func test_tap_update_throttled_by_max_age() async {
        let sut = makeSUT(indexes: [])
        sut.service.tapIndex = makeTapIndex(["saffsanity/sill": []])
        let start = Date()

        await sut.service.updateTapsIfStale(now: start, maxAge: 3600)
        await sut.service.updateTapsIfStale(now: start.addingTimeInterval(60), maxAge: 3600)
        await sut.service.updateTapsIfStale(now: start.addingTimeInterval(3601), maxAge: 3600)

        XCTAssertEqual(sut.updateCount, 2)
    }

    func test_tap_update_refreshes_index_and_outdated() async {
        let sut = makeSUT(indexes: [makeTapIndex(["saffsanity/sill": []]), makeTapIndex(["saffsanity/sill": [], "user/new": []])])
        await sut.service.refreshTaps()

        await sut.service.updateTapsIfStale(now: .now, maxAge: 0)

        XCTAssertEqual(sut.updateCount, 1)
        XCTAssertEqual(sut.service.tapIndex.taps.map(\.name), ["saffsanity/sill", "user/new"])
        XCTAssertEqual(sut.outdatedCount, 1)
    }

    func test_untrusted_tap_install_skips_the_fetch_brew_would_refuse() async throws {
        let (sut, cask) = try await loadedSillTap()

        try await sut.service.confirmTrustedInstall(cask)

        XCTAssertFalse(sut.runner.requests.contains { $0.arguments.first == "fetch" })
        XCTAssertTrue(sut.runner.requests.contains { $0.arguments.starts(with: ["install", "--cask", "saffsanity/sill/sill"]) })
    }

    func test_tap_installs_and_updates_never_run_a_separate_fetch() async throws {
        let sut = makeSUT(indexes: [makeTapIndex(["saffsanity/sill": ["sill"]], trustedCasks: ["saffsanity/sill/sill"])])
        await sut.service.refreshTaps()

        try await sut.service.install(token: "saffsanity/sill/sill")
        try await sut.service.upgrade(token: "saffsanity/sill/sill")

        XCTAssertFalse(sut.runner.requests.contains { $0.arguments.first == "fetch" })
        try await sut.service.install(token: "figma")
        XCTAssertTrue(sut.runner.requests.contains { $0.arguments.prefix(3) == ["fetch", "--cask", "figma"] })
    }

    func test_trust_is_rechecked_before_deciding_to_prompt() async throws {
        let (sut, cask) = try await loadedSillTap(trusted: true)
        sut.trust = TapTrust(taps: [], casks: [])

        try await sut.service.installRequestingTrust(cask)

        XCTAssertEqual(sut.service.pendingTrustInstall?.reference, "saffsanity/sill/sill", "uninstall dropped brew's trust")
        XCTAssertTrue(sut.runner.requests.isEmpty)
    }

    func test_cancelled_add_untaps_leftover_and_throws() async {
        let sut = makeSUT(indexes: [makeTapIndex(["user/slow": []])])
        sut.runner.onRequest = { [service = sut.service] request in
            if request.arguments == ["tap", "user/slow"] { service.cancelAddTap("user/slow") }
        }

        do {
            try await sut.service.addTap(TapAddRequest(tapName: "user/slow", remoteURL: nil, caskToken: nil))
            XCTFail("cancel must surface as CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(sut.runner.requests.contains { $0.arguments == ["untap", "user/slow"] })
    }

    func test_failed_tap_add_message_is_read_once() async {
        let sut = makeSUT(indexes: [makeTapIndex([:])])
        sut.runner.queuedResults = [BrewProcessResult(exitCode: 1, output: "Error: Invalid tap name 'user/nope'")]

        try? await sut.service.addTap(TapAddRequest(tapName: "user/nope", remoteURL: nil, caskToken: nil))

        XCTAssertNotNil(sut.service.takeTapFailureMessage("user/nope"))
        XCTAssertNil(sut.service.takeTapFailureMessage("user/nope"))
    }

    func test_install_refuses_when_a_twin_owns_the_install() async throws {
        let sut = makeSUT(indexes: [])
        updateInstalledCask(installation("foo", version: "1.0"), in: sut.service)

        try await sut.service.install(token: "user/tap/foo")

        XCTAssertTrue(sut.runner.requests.isEmpty)
        XCTAssertNotNil(sut.service.actionAlert(for: "user/tap/foo"))
    }

    func test_tap_update_waits_for_the_exclusive_lane() async {
        let sut = makeSUT(indexes: [])
        sut.service.tapIndex = makeTapIndex(["saffsanity/sill": []])
        _ = await sut.lanes.acquire(.exclusive, token: "busy") {}

        let update = Task { await sut.service.updateTapsIfStale(now: .now, maxAge: 0) }
        for _ in 0 ..< 50 { await Task.yield() }
        XCTAssertEqual(sut.updateCount, 0)

        sut.lanes.release(.exclusive)
        await update.value
        XCTAssertEqual(sut.updateCount, 1)
    }

    // MARK: - Helpers

    private final class SUT {
        let service: LocalHomebrewService
        let runner: StubBrewProcessRunner
        let lanes: HomebrewLaneLimiter
        var indexes: [TapIndex?]
        var formulae: [String] = []
        var updateCount = 0
        var trust = TapTrust(taps: [], casks: [])
        var outdatedCount = 0

        init(service: LocalHomebrewService, runner: StubBrewProcessRunner, lanes: HomebrewLaneLimiter, indexes: [TapIndex?]) {
            self.lanes = lanes
            self.service = service
            self.runner = runner
            self.indexes = indexes
        }
    }

    private func makeSUT(indexes: [TapIndex?]) -> SUT {
        let runner = StubBrewProcessRunner()
        var sut: SUT!
        let lanes = HomebrewLaneLimiter(downloadLimit: 3)
        let service = LocalHomebrewService(defaults: makeScratchDefaults("tap-workflow-\(UUID().uuidString)")) {
            $0.laneLimiter = lanes
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
            $0.tapTrustProvider = { sut.trust }
        }
        sut = SUT(service: service, runner: runner, lanes: lanes, indexes: indexes)
        return sut
    }

    private func loadedSillTap(trusted: Bool = false) async throws -> (SUT, Cask) {
        let trustedCasks: Set<String> = trusted ? ["saffsanity/sill/sill"] : []
        let sut = makeSUT(indexes: [makeTapIndex(["saffsanity/sill": ["sill"]], trustedCasks: trustedCasks)])
        await sut.service.refreshTaps()
        return (sut, try XCTUnwrap(sut.service.tapIndex.casks.first))
    }

    private func tapInstallation(_ token: String, tap: String) -> LocalCaskInstallation {
        LocalCaskInstallation(token: token, installedVersion: "1.0", installedAt: nil, appBundleNames: [], tap: tap)
    }
}
