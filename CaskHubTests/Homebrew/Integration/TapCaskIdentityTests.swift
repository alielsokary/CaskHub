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

    func test_open_failure_reports_the_cask_and_the_bundles_it_looked_for() throws {
        let spy = SpyCrashReporterProvider()
        let saved = (CrashReporter.provider, CrashReporter.isRunningTests, CrashReporter.captureCounts, CrashReporter.defaults)
        CrashReporter.provider = spy
        CrashReporter.isRunningTests = false
        CrashReporter.captureCounts = [:]
        CrashReporter.defaults = makeScratchDefaults("open-missing-crash")
        defer {
            CrashReporter.provider = saved.0
            CrashReporter.isRunningTests = saved.1
            CrashReporter.captureCounts = saved.2
            CrashReporter.defaults = saved.3
        }
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("open-missing-\(UUID().uuidString)")
        let service = LocalHomebrewService(defaults: makeScratchDefaults("open-missing-\(UUID().uuidString)")) {
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.applicationDirectories = [empty]
        }
        let installation = LocalCaskInstallation(
            token: "sill", installedVersion: "1.0", installedAt: nil, appBundleNames: ["Sill.app"], tap: "saffsanity/sill"
        )
        updateInstalledCask(installation, in: service)

        service.open(Cask.receiptRow(for: installation))

        let error = try XCTUnwrap(spy.capturedErrors.last)
        let reported = SentryProvider.reportedError(error) as NSError
        XCTAssertEqual(reported.domain, "CaskHub.AppBundleNotFound")
        XCTAssertEqual(reported.userInfo[NSDebugDescriptionErrorKey] as? String, "open · saffsanity/sill/sill")
        XCTAssertEqual(SentryProvider.fingerprint(for: error), ["CaskHub.AppBundleNotFound", "open"])
        XCTAssertEqual(spy.capturedErrorTags.last?["brew.cask"], "saffsanity/sill/sill")
        XCTAssertEqual(spy.capturedErrorTags.last?["app.source"], "homebrew")
        XCTAssertEqual(spy.capturedErrorTags.last?["app.bundle_names"], "Sill.app")
    }

    func test_report_removes_login_names_from_sudo_command_lines() throws {
        let report = try XCTUnwrap(HomebrewDiagnosticRedactor.report(
            "Error: google-drive: Failure while executing; `/usr/bin/sudo -u root -A -E LOGNAME=dev USER=dev "
                + "USERNAME=dev SUDO_USER=dev -- /usr/sbin/installer -pkg GoogleDrive.pkg -target /` exited with 1."
        ))

        XCTAssertFalse(report.headline.contains("=dev"), report.headline)
        XCTAssertTrue(report.headline.contains("LOGNAME=<user> USER=<user> USERNAME=<user> SUDO_USER=<user>"), report.headline)
    }

    func test_sentry_failure_tags_carry_the_tap_reference() async {
        let spy = SpyCrashReporterProvider()
        let saved = (CrashReporter.provider, CrashReporter.isRunningTests, CrashReporter.captureCounts, CrashReporter.defaults)
        CrashReporter.provider = spy
        CrashReporter.isRunningTests = false
        CrashReporter.captureCounts = [:]
        CrashReporter.defaults = makeScratchDefaults("tap-identity-crash")
        defer {
            CrashReporter.provider = saved.0
            CrashReporter.isRunningTests = saved.1
            CrashReporter.captureCounts = saved.2
            CrashReporter.defaults = saved.3
        }
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [
            BrewProcessResult(exitCode: 1, output: "Error: It seems the App source '/Applications/Sill.app' is not there.")
        ]
        let service = makeMutationService(runner: runner)

        try? await service.install(tapCask("sill", tap: "saffsanity/sill"))

        XCTAssertEqual(spy.capturedErrorTags.last?["brew.cask"], "saffsanity/sill/sill")
        XCTAssertEqual(spy.capturedErrorTags.last?["brew.tap"], "saffsanity/sill")
    }

    func test_report_removes_authorization_values_and_long_tokens_but_keeps_names() throws {
        let report = try XCTUnwrap(HomebrewDiagnosticRedactor.report("""
        > Authorization: Bearer abc.DEF-123_xyz
        curl: retrying with Bearer sk_live_shorter
        Error: Download failed: token 0123456789abcdefABCDEF0123456789abcdef01 rejected
        downloads/3fb265a10ab94122493b1258a5a62f73e00df2386a703b34b21b87f54793ecbc--GitHubDesktop-arm64.zip
        """))

        XCTAssertFalse(report.text.contains("abc.DEF-123_xyz"), report.text)
        XCTAssertFalse(report.text.contains("sk_live_shorter"), report.text)
        XCTAssertFalse(report.text.contains("0123456789abcdefABCDEF"), report.text)
        XCTAssertTrue(report.text.contains("<token>--GitHubDesktop-arm64.zip"), report.text)
        XCTAssertEqual(report.headline, "Error: Download failed: token <token> rejected")
    }

    func test_report_removes_cookie_key_and_password_values() throws {
        let report = try XCTUnwrap(HomebrewDiagnosticRedactor.report("""
        > Cookie: session=abc123def
        > X-Api-Key: k3yvalue
        Password:
        Error: login failed password=hunter2 api_key=zzz999 token: tkn777
        """))

        for secret in ["abc123def", "k3yvalue", "hunter2", "zzz999", "tkn777"] {
            XCTAssertFalse(report.text.contains(secret), report.text)
        }
        XCTAssertTrue(report.text.contains("Password:\nError: login failed"), report.text)
    }

    func test_known_failures_also_carry_brews_scrubbed_text() throws {
        let failure = HomebrewCommandFailure(
            arguments: ["install", "--cask", "t3-code"], exitCode: 1,
            diagnostic: "==> Fetching t3-code\nError: It seems there is already an App at "
                + "'/Users/alice/Applications/T3 Code (Beta).app'."
        )

        let report = try XCTUnwrap(failure.diagnosticReport)
        XCTAssertEqual(
            report.headline,
            "Error: It seems there is already an App at '/Users/<user>/Applications/T3 Code (Beta).app'."
        )
    }

    func test_untap_failures_group_by_message_and_report_brews_own_words() throws {
        func refusal(_ tap: String) -> HomebrewCommandFailure {
            HomebrewCommandFailure(arguments: ["untap", tap], exitCode: 1, diagnostic: """
            Error: Refusing to untap \(tap) because it contains the following installed formulae:
            \(tap)/tool
            ==> Would untap \(tap) after uninstalling the following formulae:
            \(tap)/tool
            """)
        }
        let first = refusal("alice/tools")

        XCTAssertEqual(first.stableFingerprint, refusal("bob/stuff").stableFingerprint)
        let report = try XCTUnwrap(first.diagnosticReport)
        XCTAssertEqual(
            report.headline,
            "Error: Refusing to untap alice/tools because it contains the following installed formulae:"
        )
        XCTAssertTrue(report.text.contains("\nalice/tools/tool\n==> Would untap alice/tools"), report.text)
    }

    func test_diagnostic_report_keeps_names_and_strips_private_parts() throws {
        let failure = HomebrewCommandFailure(arguments: ["tap", "probe/none"], exitCode: 1, diagnostic: """
        Cloning into '/opt/homebrew/Library/Taps/probe/homebrew-none'...
        Error: Failure while executing; `git clone https://user:s3cret@example.com/probe/homebrew-none.git` exited with 128.
        Could not write '/Users/alice/My Apps/Thing.app' for alice@example.com via git@github.com:carol/repo
        GET https://cdn.example.com/a.dmg?sig=abc&se=2026 with ghp_abcdefghijklmnopqrstuvwxyz0123
        """)
        let report = try XCTUnwrap(failure.diagnosticReport)

        XCTAssertEqual(
            report.headline,
            "Error: Failure while executing; `git clone https://<credentials>@example.com/probe/homebrew-none.git` exited with 128."
        )
        XCTAssertEqual(report.text, """
        Cloning into '/opt/homebrew/Library/Taps/probe/homebrew-none'...
        Error: Failure while executing; `git clone https://<credentials>@example.com/probe/homebrew-none.git` exited with 128.
        Could not write '/Users/<user>/My Apps/Thing.app' for <email> via git@github.com:carol/repo
        GET https://cdn.example.com/a.dmg?<query> with <token>
        """)
        XCTAssertNil(HomebrewCommandFailure(arguments: ["untap", "a/b"], exitCode: 130, diagnostic: "").diagnosticReport)
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
        await vm.projectionsSettled()
        return (vm, service)
    }

    private func tapInstallation(_ token: String, tap: String, version: String) -> LocalCaskInstallation {
        LocalCaskInstallation(token: token, installedVersion: version, installedAt: nil, appBundleNames: [], tap: tap)
    }

    private func tapCask(_ token: String, tap: String) -> Cask {
        Cask.receiptRow(for: tapInstallation(token, tap: tap, version: "1.0"))
    }
}
