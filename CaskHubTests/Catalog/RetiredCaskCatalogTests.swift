//
//  RetiredCaskCatalogTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 25/10/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class RetiredCaskCatalogTests: XCTestCase {
    func test_installed_tab_lists_every_caskroom_token() async {
        let local = await makePlatformResolvedHomebrew(defaults: makeScratchDefaults("retired-installed"))
        for (token, tap, apps) in [
            ("firefox", "homebrew/cask", ["Firefox.app"]),
            ("dead-app", "homebrew/cask", ["Dead.app"]),
            ("legacy-app", "homebrew/cask", ["Legacy.app"]),
            ("font-x", "homebrew/cask", []),
            ("foo@beta", "homebrew/cask", ["Foo Beta.app"]),
            ("gone-app", "homebrew/cask", ["Gone App.app"]),
            ("tapped-app", "other/tap", ["Tapped.app"])
        ] {
            updateInstalledCask(receiptInstallation(token, tap: tap, apps: apps), in: local)
        }
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("firefox"),
                Cask.preview(token: "dead-app", disabled: true),
                Cask.preview(token: "legacy-app", deprecated: true),
                makeCask("font-x"),
                makeCask("foo@beta"),
                makeCask("iterm2")
            ],
            localHomebrew: local
        )

        vm.selectedSidebar = .library(.installed)
        XCTAssertEqual(
            Set(vm.filteredCasks.map(\.token)),
            ["firefox", "dead-app", "legacy-app", "font-x", "foo@beta", "gone-app", "tapped-app"]
        )
        XCTAssertEqual(vm.installedCount(includingExternallyManaged: false), local.installedCaskCount)
        let rows = Dictionary(uniqueKeysWithValues: vm.filteredCasks.map { ($0.token, $0) })
        XCTAssertEqual(rows["gone-app"]?.displayName, "Gone App")
        XCTAssertEqual(rows["gone-app"]?.provenance, .installedReceipt)
        XCTAssertEqual(rows["dead-app"]?.provenance, .homebrewAPI)
        XCTAssertEqual(rows.mapValues { vm.localState(for: $0).retirement?.blocksInstall }, [
            "firefox": nil, "font-x": nil, "foo@beta": nil, "tapped-app": nil,
            "dead-app": true, "legacy-app": false, "gone-app": true
        ])
        XCTAssertEqual(rows["gone-app"].map { vm.localState(for: $0).retirement }, .removedFromHomebrew)
        XCTAssertTrue(rows.values.allSatisfy { vm.localState(for: $0).isHomebrewInstalled })

        vm.selectedSidebar = .discover(.browse)
        XCTAssertEqual(Set(vm.filteredCasks.map(\.token)), ["firefox", "iterm2"])
        XCTAssertEqual(Set(vm.casks.map(\.token)), ["firefox", "iterm2"])
    }

    func test_installed_rows_wait_for_the_api_catalog() async {
        let local = await makePlatformResolvedHomebrew(defaults: makeScratchDefaults("retired-wait"))
        updateInstalledCask(receiptInstallation("firefox", tap: "homebrew/cask", apps: ["Firefox.app"]), in: local)
        let api = MockBrewAPIClient()
        api.casksError = URLError(.notConnectedToInternet)
        let vm = makeViewModel(api: api, localHomebrew: local)

        await vm.fetchCasks()

        vm.selectedSidebar = .library(.installed)
        XCTAssertEqual(vm.filteredCasks.map(\.token), [], "No row may claim firefox was removed from Homebrew")
    }

    func test_installed_deprecated_cask_offers_updates_but_disabled_and_receipt_rows_do_not() async {
        let local = LocalHomebrewService(defaults: makeScratchDefaults("retired-updates")) {
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.brewBinaryProvider = { nil }
            $0.brewVersionProvider = { "test" }
            $0.caskPlatformProvider = { CaskPlatform(tag: "arm64_sequoia") }
            $0.homebrewOutdatedProvider = {
                HomebrewOutdatedReport(upgradable: ["legacy-app", "dead-app", "gone-app", "tapped-app"], pinned: [])
            }
        }
        await local.refresh()
        await local.refreshHomebrewOutdated()
        for (token, tap) in [
            ("legacy-app", "homebrew/cask"), ("dead-app", "homebrew/cask"),
            ("gone-app", "homebrew/cask"), ("tapped-app", "other/tap")
        ] {
            updateInstalledCask(receiptInstallation(token, tap: tap, apps: []), in: local)
        }
        let (vm, _) = await makeSUT(
            casks: [
                Cask.preview(token: "legacy-app", version: "2.0", deprecated: true),
                Cask.preview(token: "dead-app", version: "2.0", disabled: true)
            ],
            localHomebrew: local
        )

        vm.selectedSidebar = .library(.updates)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["legacy-app"])
        XCTAssertEqual(vm.updatesCount, 1)
    }

    func test_receipt_row_uninstall_sends_token_command() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner)
        updateInstalledCask(receiptInstallation("gone-app", tap: "homebrew/cask", apps: []), in: service)
        let (vm, _) = await makeSUT(casks: [makeCask("firefox")], localHomebrew: service)
        vm.selectedSidebar = .library(.installed)
        let row = try XCTUnwrap(vm.filteredCasks.first { $0.token == "gone-app" })
        XCTAssertEqual(vm.localState(for: row).uninstallAvailability, .available)

        try await service.uninstall(token: row.token)

        XCTAssertTrue(runner.requests.contains { $0.arguments.starts(with: ["uninstall", "--cask", "gone-app"]) })
    }

    func test_retired_cask_sharing_a_bundle_id_neither_adopts_nor_blocks_the_live_cask() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("retired-owner-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApplicationBundle(in: root, named: "Shared.app", bundleIdentifier: "com.example.shared")
        let local = LocalHomebrewService(defaults: makeScratchDefaults("retired-owner")) {
            $0.applicationDirectories = [root]
        }
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("old-shared", appNames: ["Shared.app"], applicationBundleIdentifiers: ["com.example.shared"]),
                makeCask("new-shared", appNames: ["Shared.app"], applicationBundleIdentifiers: ["com.example.shared"])
            ].enumerated().map { index, cask in index == 0 ? disabling(cask) : cask },
            localHomebrew: local
        )

        XCTAssertEqual(vm.adoptableCasks.map(\.token), ["new-shared"])
        XCTAssertEqual(vm.casks.map(\.token), ["new-shared"])
    }

    private func receiptInstallation(_ token: String, tap: String, apps: [String]) -> LocalCaskInstallation {
        LocalCaskInstallation(
            token: token, installedVersion: "1.0", installedAt: nil, appBundleNames: apps, tap: tap
        )
    }

    private func disabling(_ cask: Cask) -> Cask {
        var disabled = Cask.preview(token: cask.token, disabled: true)
        disabled.artifacts = cask.artifacts
        return disabled
    }
}
