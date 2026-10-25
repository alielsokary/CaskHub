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

    func test_disabled_and_removed_casks_explain_themselves_and_drop_reinstall_recoveries() async throws {
        let local = await makePlatformResolvedHomebrew(defaults: makeScratchDefaults("retired-explain"))
        for token in ["dead-app", "gone-app", "firefox"] {
            updateInstalledCask(receiptInstallation(token, tap: "homebrew/cask", apps: []), in: local)
        }
        let (vm, _) = await makeSUT(
            casks: [
                Cask.preview(
                    token: "dead-app", disabled: true,
                    disableDate: "2026-09-01", disableReason: "fails_gatekeeper_check"
                ),
                makeCask("firefox")
            ],
            localHomebrew: local
        )
        vm.selectedSidebar = .library(.installed)
        let rows = Dictionary(uniqueKeysWithValues: vm.filteredCasks.map { ($0.token, $0) })
        let dead = try XCTUnwrap(rows["dead-app"])

        let info = Dictionary(uniqueKeysWithValues: CaskInfoProjector.makeRows(from: CaskInfoProjectionInput(
            cask: dead, category: nil, downloadSize: .unknown,
            actionPresentation: local.actionPresentation(for: dead, localState: vm.localState(for: dead)),
            externalVersion: nil, installationDates: nil
        )).map { ($0.property, $0.value) })
        XCTAssertEqual(info["Disabled"], "Yes")
        XCTAssertEqual(info["Reason"], "It fails the macOS Gatekeeper check.")
        XCTAssertEqual(info["Disabled On"], try day("2026-09-01").formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)
        ))

        let warning = "Homebrew can't reinstall this app later."
        for token in ["dead-app", "gone-app"] {
            let alert = CaskActionAlertFactory.uninstallAlert(for: try XCTUnwrap(rows[token]), service: local).alert
            XCTAssertTrue(alert.informativeText.contains(warning), token)
        }
        let firefoxAlert = CaskActionAlertFactory.uninstallAlert(for: try XCTUnwrap(rows["firefox"]), service: local)
        XCTAssertFalse(firefoxAlert.alert.informativeText.contains(warning))

        let failure = CaskOperationFailure(kind: .brewCommand, message: "short", recoveries: Set(CaskRecoveryAction.allCases))
        let titles = CaskActionAlertFactory.errorAlert(for: dead, failure: failure, service: local).alert.buttons.map(\.title)
        XCTAssertFalse(titles.contains("Adopt Existing App"))
        XCTAssertFalse(titles.contains("Replace with Homebrew Version"))
        XCTAssertFalse(titles.contains("Repair & Reinstall"))
        XCTAssertTrue(titles.contains("Force Uninstall"))
    }

    func test_discover_search_appends_retired_matches_after_installable_results() async {
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("app-live", name: "Zeta App"),
                makeCask("other-live", name: "Other App"),
                Cask.preview(token: "app-dead", name: "Alpha App", disabled: true),
                Cask.preview(token: "app-old", name: "Beta App", deprecated: true),
                makeCask("font-app"),
                makeCask("app@beta")
            ],
            analytics: [("app-dead", "9999"), ("app-old", "5000"), ("app-live", "2"), ("other-live", "1")]
        )
        let retired: Set = ["app-dead", "app-old"]

        for page in DiscoverItem.allCases {
            vm.selectedSidebar = .discover(page)
            for sort in [SortOption.mostPopular, .nameAZ, .nameZA, .newest, .oldest] {
                vm.sortOption = sort
                vm.searchText = "app"
                let tokens = vm.filteredCasks.map(\.token)
                let context = "\(page) \(sort)"
                XCTAssertEqual(Set(tokens.suffix(2)), retired, context)
                XCTAssertTrue(tokens.dropLast(2).allSatisfy { !retired.contains($0) }, context)
                XCTAssertFalse(tokens.contains("font-app") || tokens.contains("app@beta"), context)
                vm.searchText = ""
                XCTAssertTrue(vm.filteredCasks.allSatisfy { !retired.contains($0.token) }, context)
            }
        }
    }

    func test_category_search_appends_only_retired_casks_in_that_category() async {
        let categories = seededCategories(
            [
                "live-player": TokenCategoryMapping(primary: "media", secondary: []),
                "dead-player": TokenCategoryMapping(primary: "media", secondary: []),
                "dead-editor": TokenCategoryMapping(primary: "office", secondary: [])
            ],
            categories: [
                "media": CategoryDefinition(displayName: "Media", icon: "play"),
                "office": CategoryDefinition(displayName: "Office", icon: "doc")
            ]
        )
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("live-player"),
                Cask.preview(token: "dead-player", disabled: true),
                Cask.preview(token: "dead-editor", disabled: true)
            ],
            categories: categories
        )

        vm.selectedSidebar = .category("media")
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["live-player"])
        XCTAssertEqual(vm.categoryCounts["media"], 1, "retired casks never count toward categories")
        vm.searchText = "dead"
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["dead-player"])
    }

    func test_library_page_search_never_appends_retired_casks() async {
        let local = await makePlatformResolvedHomebrew(defaults: makeScratchDefaults("retired-library-search"))
        updateInstalledCask(receiptInstallation("firefox", tap: "homebrew/cask", apps: []), in: local)
        let (vm, _) = await makeSUT(
            casks: [makeCask("firefox"), Cask.preview(token: "firefox-dead", disabled: true)],
            localHomebrew: local
        )

        for page in LibraryItem.allCases {
            vm.selectedSidebar = .library(page)
            vm.searchText = "firefox"
            XCTAssertFalse(vm.filteredCasks.contains { $0.token == "firefox-dead" }, "\(page)")
        }
    }

    private func day(_ iso: String) throws -> Date {
        try Date(iso, strategy: Date.ISO8601FormatStyle().year().month().day())
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
