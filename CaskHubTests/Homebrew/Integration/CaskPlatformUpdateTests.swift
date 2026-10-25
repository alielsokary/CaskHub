//
//  CaskPlatformUpdateTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 05/10/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class CaskPlatformUpdateTests: XCTestCase {
    func test_compatible_receipt_removes_phantom_updates_in_both_greedy_modes() async throws {
        for (release, receipt) in [("sequoia", "4.8.5"), ("tahoe", "5.0.5"), ("golden_gate", "5.1.0")] {
            for prefix in ["", "arm64_"] {
                let context = try await makeContext(
                    platform: CaskPlatform(tag: prefix + release),
                    receipt: receipt, report: HomebrewOutdatedReport(upgradable: ["onyx"], pinned: [])
                )
                defer { context.session.invalidateAndCancel() }
                assertUpdates(context, off: false, greedy: false)
                let cask = try XCTUnwrap(context.vm.casks.first)
                XCTAssertFalse(context.service.localState(for: cask).isOutdated)
                XCTAssertEqual(cask.version, "5.1.0", "Display metadata stays unchanged")
                XCTAssertEqual(cask.url, "https://example.com/27/OnyX.dmg")
                XCTAssertEqual(context.vm.installedCount, 1)
            }
        }
    }

    func test_older_compatible_release_is_offered_and_disappears_after_refresh() async throws {
        for tag in ["sequoia", "arm64_sequoia"] {
            let context = try await makeContext(
                platform: CaskPlatform(tag: tag), receipt: "4.8.4"
            )
            defer { context.session.invalidateAndCancel() }
            assertUpdates(context, off: true, greedy: true)
            updateInstalledCask(installation("onyx", version: "4.8.5"), in: context.service)
            await context.service.refresh()
            assertUpdates(context, off: false, greedy: false)
        }
    }

    func test_platform_resolution_works_when_homebrew_outdated_query_fails() async throws {
        let context = try await makeContext(platform: sequoia, receipt: "4.8.5", report: nil)
        defer { context.session.invalidateAndCancel() }
        XCTAssertNil(context.service.homebrewOutdated)
        assertUpdates(context, off: false, greedy: false)
    }

    func test_explicitly_unsupported_platform_wins_over_homebrew_listing() async throws {
        let context = try await makeContext(
            platform: CaskPlatform(tag: "tahoe"), receipt: "4.8.5",
            overrides: ["supported_platforms": ["arm64_tahoe"]],
            report: HomebrewOutdatedReport(upgradable: ["onyx"], pinned: [])
        )
        defer { context.session.invalidateAndCancel() }
        assertUpdates(context, off: false, greedy: false)
        XCTAssertEqual(context.vm.installedCount, 1, "Keep installed apps visible and manageable")
        let cask = try XCTUnwrap(context.vm.casks.first)
        XCTAssertEqual(context.service.localState(for: cask).uninstallAvailability, .available)
    }

    func test_exact_architecture_variant_and_missing_override_follow_homebrew() async throws {
        let overrides: [String: Any] = ["variations": ["sequoia": ["version": "4.7.0"]]]
        for (tag, receipt) in [("sequoia", "4.7.0"), ("arm64_sequoia", "5.1.0")] {
            let context = try await makeContext(
                platform: CaskPlatform(tag: tag),
                receipt: receipt, overrides: overrides
            )
            defer { context.session.invalidateAndCancel() }
            assertUpdates(context, off: false, greedy: false)
        }
    }

    func test_variant_field_presence_preserves_inheritance_and_explicit_nulls() async throws {
        struct Scenario {
            let variant: [String: Any]
            let off: Bool
            let greedy: Bool
        }
        let scenarios = [
            Scenario(variant: ["version": "4.8.5"], off: false, greedy: true),
            Scenario(variant: ["version": "4.8.5", "auto_updates": NSNull()], off: true, greedy: true),
            Scenario(variant: ["version": "4.8.5", "auto_updates": false], off: true, greedy: true),
            Scenario(variant: ["auto_updates": false], off: true, greedy: true),
            Scenario(variant: ["version": NSNull(), "auto_updates": false], off: false, greedy: false),
            Scenario(variant: ["version": "4.8.5", "disabled": true], off: false, greedy: false),
            Scenario(variant: ["version": "4.8.5", "deprecated": true], off: false, greedy: true)
        ]
        for scenario in scenarios {
            let context = try await makeContext(
                platform: sequoia, receipt: "4.8.4",
                overrides: ["auto_updates": true, "variations": ["arm64_sequoia": scenario.variant]]
            )
            defer { context.session.invalidateAndCancel() }
            assertUpdates(context, off: scenario.off, greedy: scenario.greedy)
        }
    }

    func test_self_updated_bundle_is_compared_with_the_compatible_target() async throws {
        let context = try await makeContext(
            platform: sequoia, receipt: "4.8.4", overrides: ["auto_updates": true],
            report: HomebrewOutdatedReport(upgradable: ["onyx"], pinned: []), appVersion: "4.8.5"
        )
        defer { context.session.invalidateAndCancel() }
        assertUpdates(context, off: false, greedy: false)
    }

    func test_pinned_compatible_update_stays_excluded() async throws {
        let context = try await makeContext(
            platform: sequoia, receipt: "4.8.4", report: HomebrewOutdatedReport(upgradable: [], pinned: ["onyx"])
        )
        defer { context.session.invalidateAndCancel() }
        for greedy in [false, true] {
            context.service.setGreedyUpdates(greedy)
            XCTAssertEqual(context.vm.updatesCount, 0)
        }
    }

    private let sequoia = CaskPlatform(tag: "arm64_sequoia")

    private struct Context {
        let vm: CaskCatalogViewModel
        let service: LocalHomebrewService
        let session: URLSession
    }

    private func assertUpdates(_ context: Context, off: Bool, greedy: Bool, file: StaticString = #filePath, line: UInt = #line) {
        for (enabled, expected) in [(false, off), (true, greedy)] {
            context.service.setGreedyUpdates(enabled)
            let cask = context.vm.casks[0]
            XCTAssertEqual(context.service.localState(for: cask).hasAvailableUpdate, expected, file: file, line: line)
            XCTAssertEqual(context.vm.updatesCount, expected ? 1 : 0, file: file, line: line)
            XCTAssertEqual(context.vm.filteredCasks.map(\.token), expected ? ["onyx"] : [], file: file, line: line)
            XCTAssertEqual(context.vm.updatableCasks.map(\.token), expected ? ["onyx"] : [], file: file, line: line)
        }
    }

    private func makeContext(
        platform: CaskPlatform?, receipt: String, overrides: [String: Any] = [:],
        report: HomebrewOutdatedReport? = HomebrewOutdatedReport(upgradable: [], pinned: []), appVersion: String? = nil,
        configureDependencies: (inout LocalHomebrewDependencies) -> Void = { _ in }
    ) async throws -> Context {
        var payload: [String: Any] = [
            "token": "onyx", "name": ["OnyX"], "homepage": "https://example.com", "version": "5.1.0",
            "url": "https://example.com/27/OnyX.dmg", "outdated": false, "deprecated": false, "disabled": false,
            "auto_updates": NSNull(), "artifacts": [["app": ["OnyX.app"]]],
            "supported_platforms": ["sequoia", "arm64_sequoia", "tahoe", "arm64_tahoe", "golden_gate", "arm64_golden_gate"],
            "variations": [
                "sequoia": ["version": "4.8.5"], "arm64_sequoia": ["version": "4.8.5"],
                "tahoe": ["version": "5.0.5"], "arm64_tahoe": ["version": "5.0.5"]
            ]
        ]
        payload.merge(overrides) { _, replacement in replacement }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlatformCatalogProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-Catalog": try JSONSerialization.data(withJSONObject: [payload]).base64EncodedString()]
        let session = URLSession(configuration: config)
        let service = LocalHomebrewService(defaults: makeScratchDefaults("platform-\(UUID().uuidString)")) {
            $0.caskPlatformProvider = { platform }
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.brewBinaryProvider = { nil }
            $0.brewVersionProvider = { "test" }
            $0.homebrewOutdatedProvider = { report }
            configureDependencies(&$0)
        }
        updateInstalledCask(installation("onyx", version: receipt), in: service)
        if let appVersion {
            updateInstallationSnapshot(of: service) { snapshot in
                snapshot.installationIndex = CaskInstallationIndex(
                    catalogTokens: ["onyx"], macAppStoreApplications: [:], externalCLIPaths: [:],
                    homebrewApplications: ["onyx": DetectedApplication(
                        url: URL(fileURLWithPath: "/Applications/OnyX.app"), bundleName: "OnyX.app",
                        bundleIdentifier: "com.titanium.OnyX", version: appVersion, shortVersion: appVersion, buildVersion: nil,
                        isMacAppStore: false, isDirectlyInApplicationDirectory: true
                    )]
                )
            }
        }
        let vm = CaskCatalogViewModel(
            apiClient: BrewAPIClient(session: session), categoryService: CategoryService(), recentlyAdded: RecentlyAddedService(),
            localHomebrew: service, defaults: makeScratchDefaults("platform-vm-\(UUID().uuidString)")
        )
        await service.refresh()
        await service.refreshHomebrewOutdated()
        await vm.fetchCasks()
        XCTAssertNil(vm.errorMessage)
        _ = try XCTUnwrap(vm.casks.first)
        vm.selectedSidebar = .library(.updates)
        return Context(vm: vm, service: service, session: session)
    }
}

extension CaskPlatformUpdateTests {
    func test_future_homebrew_platform_uses_its_matching_variant() async throws {
        for tag in ["future_release", "arm64_future_release"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let brew = try makePlatformBrew(in: root, output: "\"\(tag)\"")
            let context = try await makeContext(
                platform: nil, receipt: "4.8.5",
                overrides: ["supported_platforms": [tag], "variations": [tag: ["version": "4.8.5"]]]
            ) {
                $0.caskPlatformProvider = nil // Exercise the real loader through the facade.
                $0.brewBinaryProvider = { brew }
            }
            defer { context.session.invalidateAndCancel() }
            XCTAssertEqual(context.service.caskPlatform?.tag, tag)
            assertUpdates(context, off: false, greedy: false)
            updateInstalledCask(installation("onyx", version: "4.8.4"), in: context.service)
            await context.service.refresh()
            assertUpdates(context, off: true, greedy: true)
        }
    }

    func test_future_platform_still_checks_supported_platforms() async throws {
        let context = try await makeContext(
            platform: CaskPlatform(tag: "arm64_future_release"), receipt: "4.8.4",
            report: HomebrewOutdatedReport(upgradable: ["onyx"], pinned: [])
        )
        defer { context.session.invalidateAndCancel() }
        assertUpdates(context, off: false, greedy: false)
    }

    func test_platform_query_failures_never_use_the_generic_catalog_version() async throws {
        let scenarios = [
            ("\"arm64_sequoia\"", 1), ("Error: Homebrew unavailable", 0), ("\"\"", 0),
            ("null", 0), ("\"arm64 sequoia\"", 0), ("\"arm64_sequoia\"\nextra output", 0)
        ]
        for (output, status) in scenarios {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let brew = try makePlatformBrew(in: root, output: output, status: status)
            let context = try await makeContext(
                platform: nil, receipt: "4.8.4", report: HomebrewOutdatedReport(upgradable: ["onyx"], pinned: [])
            ) {
                $0.caskPlatformProvider = nil
                $0.brewBinaryProvider = { brew }
            }
            defer { context.session.invalidateAndCancel() }
            XCTAssertNil(context.service.caskPlatform, "Output: \(output), status: \(status)")
            assertUpdates(context, off: false, greedy: false)
        }
    }

    func test_missing_homebrew_does_not_establish_update_eligibility() async throws {
        let context = try await makeContext(platform: nil, receipt: "4.8.4") {
            $0.caskPlatformProvider = nil
        }
        defer { context.session.invalidateAndCancel() }
        assertUpdates(context, off: false, greedy: false)
    }

    func test_platform_refresh_caches_invalidates_and_recovers_update_eligibility() async throws {
        var platform: CaskPlatform?
        var queries = 0
        let context = try await makeContext(platform: nil, receipt: "4.8.4") {
            $0.caskPlatformProvider = {
                queries += 1
                return platform
            }
        }
        defer { context.session.invalidateAndCancel() }
        XCTAssertEqual(queries, 1)
        assertUpdates(context, off: false, greedy: false)

        for nextPlatform in [sequoia, nil, sequoia] {
            let previousRevision = context.service.catalogStateRevision
            platform = nextPlatform
            await context.service.refresh()
            XCTAssertGreaterThan(context.service.catalogStateRevision, previousRevision)
            let queryCount = queries
            for _ in 0 ..< 10 {
                assertUpdates(context, off: platform != nil, greedy: platform != nil)
            }
            XCTAssertEqual(queries, queryCount, "Reading catalog state must use the cached platform")
            XCTAssertEqual(context.service.caskPlatform, platform)
        }
        XCTAssertEqual(queries, 4)
        context.service.invalidateBrewVersion()
        XCTAssertNil(context.service.caskPlatform)
        assertUpdates(context, off: false, greedy: false)
        await context.service.refresh()
        assertUpdates(context, off: true, greedy: true)
        XCTAssertEqual(queries, 5)
    }

    func test_retirement_resolves_reason_date_and_replacement_per_platform() async throws {
        let casks = try await decodeCatalog([
            ["token": "tomatobar", "disabled": true, "disable_date": "2026-09-01",
             "disable_reason": "fails_gatekeeper_check"],
            ["token": "codex-app", "deprecated": true, "deprecation_date": "2026-07-12",
             "deprecation_reason": "discontinued", "deprecation_replacement_cask": "chatgpt"],
            ["token": "active-trader-pro", "deprecated": true, "deprecation_date": "2025-12-17",
             "deprecation_reason": "discontinued", "disable_date": "2026-12-17", "disable_reason": NSNull()],
            ["token": "both-flags", "deprecated": true, "deprecation_date": "2025-06-11",
             "deprecation_reason": "unmaintained", "disabled": true, "disable_date": "2026-06-11",
             "disable_reason": "unmaintained", "disable_replacement_formula": "op"],
            ["token": "adrive", "variations": ["golden_gate": [
                "disabled": true, "disable_date": "2026-09-01", "disable_reason": "fails_gatekeeper_check"
            ]]],
            ["token": "explicit-null", "deprecated": true, "deprecation_date": "2026-01-02",
             "deprecation_replacement_cask": "chatgpt",
             "variations": ["arm64_tahoe": ["deprecation_replacement_cask": NSNull()]]],
            ["token": "live"]
        ])
        let arm = CaskPlatform(tag: "arm64_golden_gate")

        XCTAssertEqual(casks["tomatobar"]?.retirement(for: arm), .disabled(
            reason: "fails_gatekeeper_check", disabledOn: try day("2026-09-01"), replacement: nil
        ))
        XCTAssertEqual(casks["codex-app"]?.retirement(for: nil), .deprecated(
            reason: "discontinued", deprecatedOn: try day("2026-07-12"),
            plannedDisableDate: try day("2027-07-12"), replacement: .cask("chatgpt")
        ))
        XCTAssertEqual(casks["active-trader-pro"]?.retirement(for: arm), .deprecated(
            reason: "discontinued", deprecatedOn: try day("2025-12-17"),
            plannedDisableDate: try day("2026-12-17"), replacement: nil
        ))
        XCTAssertEqual(casks["both-flags"]?.retirement(for: arm), .disabled(
            reason: "unmaintained", disabledOn: try day("2026-06-11"), replacement: .formula("op")
        ))
        XCTAssertEqual(casks["adrive"]?.retirement(for: CaskPlatform(tag: "golden_gate")), .disabled(
            reason: "fails_gatekeeper_check", disabledOn: try day("2026-09-01"), replacement: nil
        ))
        XCTAssertNil(casks["adrive"]?.retirement(for: arm))
        XCTAssertEqual(casks["explicit-null"]?.retirement(for: CaskPlatform(tag: "arm64_tahoe")), .deprecated(
            reason: nil, deprecatedOn: try day("2026-01-02"), plannedDisableDate: try day("2027-01-02"), replacement: nil
        ))
        XCTAssertNil(casks["live"]?.retirement(for: arm))
        XCTAssertEqual(casks["tomatobar"]?.retirement(for: arm)?.blocksInstall, true)
        XCTAssertEqual(casks["codex-app"]?.retirement(for: arm)?.blocksInstall, false)
    }

    private func day(_ iso: String) throws -> Date {
        try Date(iso, strategy: Date.ISO8601FormatStyle().year().month().day())
    }

    private func decodeCatalog(_ overrides: [[String: Any]]) async throws -> [String: Cask] {
        let payloads = overrides.map { override in
            var payload: [String: Any] = [
                "name": ["App"], "homepage": "https://example.com", "version": "1.0",
                "outdated": false, "deprecated": false, "disabled": false
            ]
            payload.merge(override) { _, replacement in replacement }
            return payload
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlatformCatalogProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-Catalog": try JSONSerialization.data(withJSONObject: payloads).base64EncodedString()]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let casks = try await BrewAPIClient(session: session).fetchAllCasks()
        return Dictionary(uniqueKeysWithValues: casks.map { ($0.token, $0) })
    }

    private func makePlatformBrew(in root: URL, output: String, status: Int = 0) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let brew = root.appendingPathComponent("brew")
        let quotedOutput = "'" + output.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        let script = """
        #!/bin/sh
        [ "$1" = ruby ] && [ "$2" = -rjson ] && [ "$3" = -e ] || exit 90
        [ "$4" = 'puts JSON.generate(Homebrew::SimulateSystem.current_tag.to_s)' ] || exit 91
        [ "$HOMEBREW_NO_AUTO_UPDATE" = 1 ] || exit 92
        [ "$HOMEBREW_DEVELOPER" = 1 ] || exit 93
        printf '%s\\n' \(quotedOutput)
        exit \(status)
        """
        try script.write(to: brew, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        return brew
    }
}

private final class PlatformCatalogProtocol: URLProtocol {
    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let encoded = request.value(forHTTPHeaderField: "X-Test-Catalog"),
              let catalog = Data(base64Encoded: encoded),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: url.path == "/api/cask.json" ? catalog : Data(#"{"items":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
