//
//  ExternallyManagedCasksTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 05/10/2026.
//

@testable import CaskHub
import XCTest

final class ExternallyManagedCasksTests: XCTestCase {
    @MainActor
    func test_installed_separates_external_apps_and_counts_only_visible_sources() async {
        let (model, local) = await makeCatalog()

        XCTAssertEqual(model.filteredCasks.map(\.token), ["current", "managed"])
        XCTAssertEqual(model.updatableCasks.map(\.token), ["managed"])
        XCTAssertEqual(model.updatesCount, 1)
        XCTAssertEqual(model.filteredExternallyManagedCasks.map(\.token), ["manual", "store", "command", "package"])
        XCTAssertEqual(model.installedCount(includingExternallyManaged: true), 6)
        XCTAssertEqual(model.installedCount(includingExternallyManaged: false), 2)
        XCTAssertEqual(model.filteredCasks.count + model.filteredExternallyManagedCasks.count, 6)

        local.setAdoptIgnored("manual", true)
        XCTAssertFalse(model.adoptableCasks.contains { $0.token == "manual" })
        XCTAssertTrue(model.filteredExternallyManagedCasks.contains { $0.token == "manual" })

        // Adopting an app moves it out of the external section on the next snapshot.
        updateInstalledCask(installation("manual", version: "1.0"), in: local)
        XCTAssertEqual(model.filteredExternallyManagedCasks.map(\.token), ["store", "command", "package"])
        XCTAssertEqual(model.filteredCasks.map(\.token), ["manual", "current", "managed"])
        XCTAssertEqual(model.installedCount(includingExternallyManaged: true), 6)
        XCTAssertEqual(model.installedCount(includingExternallyManaged: false), 3)
        XCTAssertEqual(model.updatesCount, 2)

        updateInstallationSnapshot(of: local) {
            $0.externalPackageInstallations = [:]
            $0.externalPackageApplicationOwners = [:]
        }
        XCTAssertEqual(model.filteredExternallyManagedCasks.map(\.token), ["store", "command"])
        XCTAssertEqual(model.installedCount(includingExternallyManaged: true), 5)

        model.selectedSidebar = .library(.updates)
        XCTAssertEqual(model.filteredCasks.map(\.token), ["manual", "managed"])
    }

    @MainActor
    func test_external_section_uses_installed_search_and_sort_without_changing_sidebar_totals() async {
        let (model, _) = await makeCatalog()
        model.sortOption = .nameZA
        XCTAssertEqual(model.filteredExternallyManagedCasks.map(\.token), ["package", "command", "store", "manual"])

        model.searchText = "store"
        XCTAssertEqual(model.filteredExternallyManagedCasks.map(\.token), ["store"])
        XCTAssertTrue(model.filteredCasks.isEmpty)
        XCTAssertEqual(model.updatesCount, 1)
        XCTAssertEqual(model.installedCount(includingExternallyManaged: true), 6)
        XCTAssertEqual(model.installedCount(includingExternallyManaged: false), 2)

        model.searchText = "not installed"
        XCTAssertTrue(model.filteredExternallyManagedCasks.isEmpty)
        model.searchText = ""
        XCTAssertEqual(model.filteredExternallyManagedCasks.count, 4)
    }

    @MainActor
    private func makeCatalog() async -> (CaskCatalogViewModel, LocalHomebrewService) {
        let local = await makePlatformResolvedHomebrew(defaults: makeScratchDefaults(UUID().uuidString))
        let manual = makeCask("manual", name: "Alpha", version: "2.0", appNames: ["Alpha.app"])
        let store = makeCask(
            "store", name: "Beta", appNames: ["Beta.app"],
            applicationBundleIdentifiers: ["com.example.beta"]
        )
        let package = makeCask(
            "package", name: "Gamma", packageIdentifiers: ["com.example.gamma"],
            packageAppNames: ["Gamma.app"]
        )
        let (model, _) = await makeSUT(casks: [
            manual, store, package,
            makeCask("managed", version: "2.0"),
            makeCask("current"),
            makeCask("absent", name: "Not installed"),
            makeCask("command", binaryNames: ["command"])
        ], localHomebrew: local)
        seedExternalInstallation(of: manual, version: "1.0", in: local)
        seedExternalInstallation(of: package, version: "1.0", in: local)
        updateInstallationSnapshot(of: local) {
            $0.installedCasks = [
                "managed": installation("managed", version: "1.0"),
                "current": installation("current", version: "1.0")
            ]
            $0.macAppStoreAppNames = ["Beta.app"]
            $0.macAppStoreBundleIdentifiers = ["Beta.app": ["com.example.beta"]]
            $0.detectedApplications.append(makeDetectedApplication(
                "Beta.app", id: "com.example.beta", version: "1.0", isMacAppStore: true
            ))
            $0.externalBinaryPaths = ["command": URL(fileURLWithPath: "/external/bin/command")]
        }
        model.selectedSidebar = .library(.installed)
        return (model, local)
    }
}

final class ThirdPartyTapCasksTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var caskroom: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fm.temporaryDirectory.appendingPathComponent("tap-\(UUID().uuidString)")
        caskroom = root.appendingPathComponent("Caskroom")
        try fm.createDirectory(at: caskroom, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func makeEntry(_ token: String, tap: String, definition: String? = nil) throws {
        let entry = caskroom.appendingPathComponent(token)
        try fm.createDirectory(
            at: entry.appendingPathComponent("0.7.2"), withIntermediateDirectories: true
        )
        let metadata = entry.appendingPathComponent(".metadata")
        let casks = metadata.appendingPathComponent("0.7.2/20260101000000.000/Casks")
        try fm.createDirectory(at: casks, withIntermediateDirectories: true)
        let receipt: [String: Any] = [
            "source": ["tap": tap],
            "uninstall_artifacts": [["app": ["Gizmo.app"]]]
        ]
        try JSONSerialization.data(withJSONObject: receipt)
            .write(to: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
        try Data((definition ?? "{}").utf8).write(to: casks.appendingPathComponent("\(token).json"))
    }

    private func scan() -> [String: LocalCaskInstallation] {
        HomebrewInstallationScanner.scanCaskroom(
            at: caskroom, fileManager: fm, applicationDirectories: []
        )
    }

    func test_receipt_reports_its_tap() throws {
        let data = try JSONSerialization.data(withJSONObject: ["source": ["tap": "acme/tap"]])
        XCTAssertEqual(try InstallReceipt(jsonData: data).tap, "acme/tap")
        XCTAssertNil(try InstallReceipt(jsonData: Data("{}".utf8)).tap)
    }

    func test_scan_builds_a_cask_from_the_receipt_for_a_third_party_tap() throws {
        try makeEntry("gizmo", tap: "acme/tap")
        try makeEntry("firefox", tap: "homebrew/cask")

        let installations = scan()
        XCTAssertNil(Cask.installedFromTap(try XCTUnwrap(installations["firefox"])))

        let cask = try XCTUnwrap(Cask.installedFromTap(try XCTUnwrap(installations["gizmo"])))
        XCTAssertEqual(cask.token, "gizmo")
        XCTAssertEqual(cask.fullToken, "acme/tap/gizmo")
        XCTAssertEqual(cask.displayName, "Gizmo")
        XCTAssertEqual(cask.version, "0.7.2")
        XCTAssertEqual(cask.appArtifactNames, ["Gizmo.app"])
        XCTAssertEqual(cask.metaLine(downloads: nil), "v0.7.2 · acme/tap")
    }

    func test_scan_prefers_the_installed_cask_definition() throws {
        try makeEntry("gizmo", tap: "acme/tap", definition: """
        {"token":"gizmo","full_token":"acme/tap/gizmo","tap":"acme/tap",
         "name":["Gizmo Pro"],"desc":"Find places","homepage":"https://example.com",
         "version":"0.7.2","outdated":false,"deprecated":false,"disabled":false}
        """)
        let cask = try XCTUnwrap(Cask.installedFromTap(try XCTUnwrap(scan()["gizmo"])))
        XCTAssertEqual(cask.displayName, "Gizmo Pro")
        XCTAssertEqual(cask.desc, "Find places")
        XCTAssertEqual(cask.homepage, "https://example.com")
        XCTAssertEqual(cask.thirdPartyTap, "acme/tap")
    }

    @MainActor
    func test_installed_library_lists_tap_casks_and_lets_them_replace_a_colliding_catalog_cask() async {
        let local = await makePlatformResolvedHomebrew(defaults: makeScratchDefaults(UUID().uuidString))
        let (model, _) = await makeSUT(casks: [
            makeCask("sampleapp", version: "0.1.0"),
            makeCask("other", version: "1.0")
        ], localHomebrew: local)
        updateInstalledCask(
            LocalCaskInstallation(
                token: "sampleapp", installedVersion: "0.12.4", installedAt: nil,
                appBundleNames: ["SampleApp.app"], tap: "other/tap"
            ),
            in: local
        )
        updateInstalledCask(
            LocalCaskInstallation(
                token: "gizmo", installedVersion: "0.7.2", installedAt: nil,
                appBundleNames: ["Gizmo.app"], tap: "acme/tap"
            ),
            in: local
        )
        model.selectedSidebar = .library(.installed)

        XCTAssertEqual(Set(model.filteredCasks.map(\.token)), ["sampleapp", "gizmo"])
        XCTAssertEqual(model.installedCount, 2)
        XCTAssertEqual(model.filteredCasks.first { $0.token == "sampleapp" }?.tap, "other/tap")
        XCTAssertEqual(model.updatesCount, 0)
        XCTAssertEqual(model.localState(for: makeCask("gizmo")).uninstallAvailability, .available)

        model.selectedSidebar = .discover(.browse)
        XCTAssertEqual(Set(model.filteredCasks.map(\.token)), ["sampleapp", "other"])
        XCTAssertNil(model.filteredCasks.first { $0.token == "sampleapp" }?.tap)
    }

    @MainActor
    func test_tap_catalog_joins_the_catalog_and_official_tokens_win_collisions() {
        let official = [makeCask("zed"), makeCask("shared")]
        let tapCasks = [
            tapCask("widget", tap: "acme/apps"),
            tapCask("shared", tap: "acme/apps"),
            tapCask("old", tap: "acme/apps", deprecated: true)
        ]
        XCTAssertEqual(
            CaskCatalogViewModel.combining(official: official, tapCasks: tapCasks).map(\.token),
            ["zed", "shared", "widget"]
        )
    }

    @MainActor
    func test_refreshing_taps_adds_their_casks_and_lists_them_by_tap() async {
        let local = await makeTapHomebrew(
            taps: [HomebrewTap(name: "acme/apps", caskTokens: ["acme/apps/widget"])],
            casks: [tapCask("widget", tap: "acme/apps", version: "0.3.0")]
        )
        let (model, _) = await makeSUT(casks: [makeCask("zed")], localHomebrew: local)
        await model.refreshTaps()

        XCTAssertEqual(model.casks.map(\.token), ["zed", "widget"])
        XCTAssertEqual(model.casks(inTap: "acme/apps").map(\.token), ["widget"])
        model.selectedSidebar = .tap("acme/apps")
        XCTAssertEqual(model.filteredCasks.map(\.token), ["widget"])
        model.selectedSidebar = .discover(.browse)
        XCTAssertEqual(Set(model.filteredCasks.map(\.token)), ["zed", "widget"])
    }

    @MainActor
    func test_installed_tap_cask_reports_updates_from_its_tap_catalog() async {
        let local = await makeTapHomebrew(
            taps: [HomebrewTap(name: "acme/apps", caskTokens: ["acme/apps/widget"])],
            casks: [tapCask("widget", tap: "acme/apps", version: "0.3.0")]
        )
        let (model, _) = await makeSUT(localHomebrew: local)
        await model.refreshTaps()
        updateInstalledCask(
            LocalCaskInstallation(
                token: "widget", installedVersion: "0.2.1", installedAt: nil,
                appBundleNames: ["Widget.app"], tap: "acme/apps"
            ),
            in: local
        )

        XCTAssertEqual(model.updatableCasks.map(\.token), ["widget"])
        XCTAssertEqual(model.installedCasks.first?.version, "0.3.0")
        XCTAssertEqual(model.installedCasks.count, 1)
    }

    @MainActor
    func test_adding_and_removing_a_tap_refreshes_the_catalog() async {
        let manager = StubTapManager()
        let local = LocalHomebrewService(defaults: makeScratchDefaults(UUID().uuidString)) {
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
            $0.caskPlatformProvider = { CaskPlatform(tag: "arm64_sequoia") }
            $0.tapManager = manager
        }
        let (model, _) = await makeSUT(casks: [makeCask("zed")], localHomebrew: local)

        manager.snapshot = HomebrewTapSnapshot(
            taps: [HomebrewTap(name: "acme/apps", caskTokens: ["acme/apps/widget"])],
            casks: [tapCask("widget", tap: "acme/apps")]
        )
        let added = await model.addTap("acme/apps", remote: nil)
        XCTAssertTrue(added.succeeded)
        XCTAssertEqual(model.casks.map(\.token), ["zed", "widget"])
        XCTAssertEqual(manager.added, ["acme/apps"])

        manager.snapshot = HomebrewTapSnapshot(taps: [], casks: [])
        let removed = await model.removeTap("acme/apps")
        XCTAssertTrue(removed.succeeded)
        XCTAssertEqual(model.casks.map(\.token), ["zed"])

        manager.succeeds = false
        let failed = await model.addTap("acme/other", remote: nil)
        XCTAssertFalse(failed.succeeded)
        XCTAssertEqual(model.casks.map(\.token), ["zed"])
    }

    @MainActor
    func test_refreshing_taps_runs_brew_update_and_picks_up_new_casks() async {
        let manager = StubTapManager()
        let local = LocalHomebrewService(defaults: makeScratchDefaults(UUID().uuidString)) {
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
            $0.caskPlatformProvider = { CaskPlatform(tag: "arm64_sequoia") }
            $0.homebrewOutdatedProvider = { HomebrewOutdatedReport(upgradable: ["widget"], pinned: []) }
            $0.tapManager = manager
        }
        let (model, _) = await makeSUT(localHomebrew: local)
        manager.snapshot = HomebrewTapSnapshot(
            taps: [HomebrewTap(name: "acme/apps", caskTokens: ["acme/apps/widget"])],
            casks: [tapCask("widget", tap: "acme/apps", version: "0.4.0")]
        )

        let result = await model.updateTaps()

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(manager.updates, 1)
        XCTAssertEqual(model.casks.map(\.version), ["0.4.0"])
        XCTAssertEqual(local.homebrewOutdated?.upgradable, ["widget"])
    }

    func test_tap_icons_are_looked_up_in_the_tap_repository_only() throws {
        let cask = Cask.installedFromTap(LocalCaskInstallation(
            token: "widget", installedVersion: "1", installedAt: nil,
            appBundleNames: [], tap: "acme/apps"
        ))
        XCTAssertEqual(
            CaskIconURL.tapIconURLs(for: try XCTUnwrap(cask)).map(\.absoluteString),
            [
                "https://raw.githubusercontent.com/acme/homebrew-apps/HEAD/Icons/widget.png",
                "https://raw.githubusercontent.com/acme/homebrew-apps/HEAD/icons/widget.png"
            ]
        )
        XCTAssertEqual(cask?.iconKey, "acme--apps--widget")
        XCTAssertTrue(CaskIconURL.tapIconURLs(for: Cask.preview(token: "zed")).isEmpty)
    }

    @MainActor
    func test_installing_a_tap_cask_uses_its_full_token() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeMutationService(runner: runner)
        try await service.install(tapCask("widget", tap: "acme/apps"))

        XCTAssertEqual(runner.requests.map(\.arguments), [
            ["fetch", "--cask", "acme/apps/widget"],
            ["install", "--cask", "acme/apps/widget"]
        ])
    }

    @MainActor
    private func tapCask(
        _ token: String,
        tap: String,
        version: String = "0.2.1",
        deprecated: Bool = false
    ) -> Cask {
        var cask = makeCask(token, version: version)
        cask = Cask(
            token: token, fullToken: "\(tap)/\(token)", tap: tap, name: [token], desc: nil,
            homepage: "https://example.com", url: nil, sha256: nil, version: version,
            bundleVersion: nil, bundleShortVersion: nil, outdated: false, deprecated: deprecated,
            disabled: false, autoUpdates: nil, variations: nil, supportedPlatforms: nil,
            conflictsWith: nil, artifacts: cask.artifacts
        )
        return cask
    }

    @MainActor
    private func makeTapHomebrew(taps: [HomebrewTap], casks: [Cask]) async -> LocalHomebrewService {
        let manager = StubTapManager()
        manager.snapshot = HomebrewTapSnapshot(taps: taps, casks: casks)
        let local = LocalHomebrewService(defaults: makeScratchDefaults(UUID().uuidString)) {
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
            $0.caskPlatformProvider = { CaskPlatform(tag: "arm64_sequoia") }
            $0.tapManager = manager
        }
        await local.refresh()
        return local
    }
}

private final class StubTapManager: HomebrewTapManaging, @unchecked Sendable {
    var snapshot = HomebrewTapSnapshot(taps: [], casks: [])
    var succeeds = true
    private(set) var added: [String] = []
    private(set) var updates = 0

    func load(from _: URL?) async -> HomebrewTapSnapshot? {
        snapshot
    }

    func add(_ name: String, remote _: String?, using _: URL?) async -> HomebrewTapCommandResult {
        if succeeds { added.append(name) }
        return HomebrewTapCommandResult(succeeded: succeeds, output: "")
    }

    func remove(_ name: String, using _: URL?) async -> HomebrewTapCommandResult {
        HomebrewTapCommandResult(succeeded: succeeds, output: "")
    }

    func update(using _: URL?) async -> HomebrewTapCommandResult {
        updates += 1
        return HomebrewTapCommandResult(succeeded: succeeds, output: "")
    }
}
