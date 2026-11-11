//
//  TapCaskIdentityTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/11/2026.
//

@testable import CaskHub
import Sentry
import XCTest

@MainActor
final class TapCaskIdentityTests: XCTestCase {
    private var analyticsSpy: SpyAnalyticsProvider!
    private var originalProvider: AnalyticsProvider!
    private var originalMetrics: SentryMetricsApiProtocol!
    private var originalDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        analyticsSpy = SpyAnalyticsProvider()
        originalProvider = Analytics.provider
        originalMetrics = Analytics.metrics
        originalDefaults = Analytics.defaults
        Analytics.provider = analyticsSpy
        Analytics.metrics = analyticsSpy
        Analytics.defaults = makeScratchDefaults("tap-identity-analytics")
    }

    override func tearDown() {
        Analytics.provider = originalProvider
        Analytics.metrics = originalMetrics
        Analytics.defaults = originalDefaults
        super.tearDown()
    }

    func test_installed_tap_cask_does_not_resolve_to_official_twin() async throws {
        let (vm, service) = await makeSUT(
            official: [makeCask("opensuperwhisper", version: "0.1.0")],
            installed: [tapInstallation("opensuperwhisper", tap: "my-monkeys/tap", version: "0.12.4")],
            outdated: HomebrewOutdatedReport(upgradable: ["opensuperwhisper"], pinned: [])
        )
        let official = try XCTUnwrap(vm.catalogCask(for: "opensuperwhisper"))

        let state = service.localState(for: official)
        XCTAssertEqual(state.foreignInstallationSource, "my-monkeys/tap")
        XCTAssertNil(state.installationSource)
        XCTAssertFalse(state.isOutdated)
        XCTAssertFalse(state.hasAvailableUpdate)

        vm.selectedSidebar = .library(.updates)
        XCTAssertEqual(vm.filteredCasks.map(\.id), ["my-monkeys/tap/opensuperwhisper"])
    }

    func test_receipt_row_for_tap_cask_keys_on_reference() async throws {
        let (vm, _) = await makeSUT(
            official: [makeCask("opensuperwhisper", version: "0.1.0")],
            installed: [tapInstallation("opensuperwhisper", tap: "my-monkeys/tap", version: "0.12.4")]
        )

        vm.selectedSidebar = .library(.installed)

        XCTAssertEqual(vm.filteredCasks.map(\.id), ["my-monkeys/tap/opensuperwhisper"])
        let row = try XCTUnwrap(vm.filteredCasks.first)
        XCTAssertEqual(vm.localState(for: row).installationSource, .homebrew)
    }

    func test_install_tap_cask_passes_full_reference_to_brew() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner)

        try await service.install(tapCask("sill", tap: "saffsanity/sill"))

        XCTAssertTrue(runner.requests.contains { $0.arguments.starts(with: ["install", "--cask", "saffsanity/sill/sill"]) })
        XCTAssertFalse(runner.requests.contains { $0.arguments.contains("sill") })
    }

    func test_operation_state_for_twins_is_separate() async throws {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [BrewProcessResult(exitCode: 1, output: "Error: download failed")]
        let service = makeMutationService(runner: runner)

        try? await service.install(tapCask("sill", tap: "saffsanity/sill"))

        XCTAssertNotNil(service.operationStore.state(for: "saffsanity/sill/sill"))
        XCTAssertNil(service.operationStore.state(for: "sill"))
    }

    func test_analytics_hide_tap_cask_names() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner)

        try await service.install(tapCask("sill", tap: "saffsanity/sill"))

        let caskValues = analyticsSpy.signals.compactMap { $0.parameters["cask"] }
        XCTAssertFalse(caskValues.isEmpty)
        XCTAssertEqual(Set(caskValues), ["third-party"])
    }

    func test_sentry_error_hides_tap_cask_name() {
        let sanitized = SentryProvider.sanitizedForReporting(
            LocalHomebrewError.appBundleNotFound(token: "saffsanity/sill/sill")
        )

        XCTAssertFalse((sanitized as? LocalizedError)?.errorDescription?.contains("saffsanity") ?? true)
    }

    func test_presentation_shows_installed_from_source_disabled() async throws {
        let (vm, service) = await makeSUT(
            official: [makeCask("opensuperwhisper", version: "0.1.0")],
            installed: [tapInstallation("opensuperwhisper", tap: "my-monkeys/tap", version: "0.12.4")]
        )
        let official = try XCTUnwrap(vm.catalogCask(for: "opensuperwhisper"))

        let presentation = service.actionPresentation(for: official)

        XCTAssertEqual(presentation.blockingInstallSource, "my-monkeys/tap")
        XCTAssertFalse(presentation.localState.isHomebrewInstalled)
    }

    // MARK: - Helpers

    private func makeSUT(
        official: [Cask],
        installed: [LocalCaskInstallation],
        outdated: HomebrewOutdatedReport = HomebrewOutdatedReport(upgradable: [], pinned: [])
    ) async -> (CaskCatalogViewModel, LocalHomebrewService) {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("tap-identity-\(UUID().uuidString)")) {
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.brewBinaryProvider = { nil }
            $0.brewVersionProvider = { "test" }
            $0.homebrewOutdatedProvider = { outdated }
        }
        for installation in installed {
            updateInstalledCask(installation, in: service)
        }
        let api = MockBrewAPIClient()
        api.casks = official
        let vm = makeViewModel(api: api, localHomebrew: service)
        await service.refresh()
        await service.refreshHomebrewOutdated()
        await vm.fetchCasks()
        return (vm, service)
    }

    private func tapInstallation(_ token: String, tap: String, version: String) -> LocalCaskInstallation {
        LocalCaskInstallation(token: token, installedVersion: version, installedAt: nil, appBundleNames: [], tap: tap)
    }

    private func tapCask(_ token: String, tap: String) -> Cask {
        Cask.receiptRow(for: tapInstallation(token, tap: tap, version: "1.0"))
    }
}
