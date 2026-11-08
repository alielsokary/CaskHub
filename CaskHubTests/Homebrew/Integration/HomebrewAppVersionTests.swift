//
//  HomebrewAppVersionTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 19/09/2026.
//  Copyright © 2026 BuildingLink. All rights reserved.
//

@testable import CaskHub
import XCTest

private struct DeliveryScenario {
    let receipt: String
    let tap: String
    let short: String
    let build: String
    let expected: Bool
}

private struct GreedyScenario {
    let homebrew: Set<String>?
    var receipt = "1.1.7"
    var receiptApp = "Antinote.app"
    var appRemoved = false
    var pinned = false
    let short: String
    let off: Bool
    let greedy: Bool
}

@MainActor
final class HomebrewAppVersionTests: XCTestCase {
    func test_self_updated_app_uses_bundle_version_and_preserves_update_opt_in() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeInstallation(in: root)
        let service = makeService(in: root)
        await service.refresh()
        let (vm, _) = await makeSUT(
            casks: [makeAntinote()], categories: makeCategories(), localHomebrew: service
        )
        let cask = try XCTUnwrap(vm.casks.first)
        XCTAssertEqual(infoValues(for: cask, service: service)[String(localized: "Installed Version")], "2.1.0")
        vm.selectedSidebar = .library(.updates)

        for (version, expectedOutdated) in [("2.1.0", true), ("2.1.3", false), ("2.2.0", false)] {
            try setApplicationVersion(version, at: app)
            await service.refresh()
            for greedy in [false, true] {
                service.setGreedyUpdates(greedy)
                let values = infoValues(for: cask, service: service)
                XCTAssertEqual(values[String(localized: "Installed Version")], version)
                XCTAssertEqual(values[String(localized: "Outdated")],
                               expectedOutdated ? String(localized: "Yes") : String(localized: "No"))
                XCTAssertEqual(service.localState(for: cask).hasAvailableUpdate, greedy && expectedOutdated)
                XCTAssertEqual(vm.updatesCount, greedy && expectedOutdated ? 1 : 0)
                XCTAssertEqual(vm.filteredCasks.map(\.token), greedy && expectedOutdated ? ["antinote"] : [])
                XCTAssertEqual(service.installationSnapshot.installedCasks["antinote"]?.installedVersion, "1.1.7")
            }
        }
    }

    func test_composite_versions_use_installed_release_and_build_for_updates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeInstallation(in: root)
        let service = makeService(in: root)
        await service.refresh()
        let (vm, _) = await makeSUT(
            casks: [makeAntinote(version: "4.2.19,317")], categories: makeCategories(), localHomebrew: service
        )
        let cask = try XCTUnwrap(vm.casks.first)
        vm.selectedSidebar = .library(.updates)
        let scenarios: [((String, String?), Bool)] = [
            (("4.2.18", "999"), true),
            (("4.2.19", "316"), true),
            (("4.2.19", "317"), false),
            (("4.2.19", "318"), false),
            (("4.2.20", "1"), false),
            (("4.2.19", nil), false),
            (("4.2.19", "317beta"), false),
            (("4.2.19", ""), false)
        ]
        for ((release, build), expectedOutdated) in scenarios {
            try setApplicationVersion(release, at: app)
            try setBuildVersion(build, at: app)
            await service.refresh()
            XCTAssertEqual(service.installationSnapshot.installationIndex.homebrewApplications[cask.token]?.buildVersion, build)
            for greedy in [false, true] {
                service.setGreedyUpdates(greedy)
                let values = infoValues(for: cask, service: service)
                XCTAssertEqual(values[String(localized: "Installed Version")], release)
                XCTAssertEqual(values[String(localized: "Outdated")],
                               expectedOutdated ? String(localized: "Yes") : String(localized: "No"))
                XCTAssertEqual(service.localState(for: cask).hasAvailableUpdate, greedy && expectedOutdated)
                XCTAssertEqual(vm.updatesCount, greedy && expectedOutdated ? 1 : 0)
                XCTAssertEqual(vm.filteredCasks.map(\.token), greedy && expectedOutdated ? [cask.token] : [])
            }
        }
    }

    func test_updates_are_offered_only_when_brew_can_deliver_a_newer_app() async throws {
        let scenarios = [
            DeliveryScenario(receipt: "1.16.0", tap: "1.16.0", short: "1.15.0", build: "294", expected: false),
            DeliveryScenario(receipt: "2.19.1,6046815158665216", tap: "2.19.1,6046815158665216",
                short: "2.19.1", build: "2.19.1", expected: false),
            DeliveryScenario(receipt: "11.1.1,1111", tap: "11.1.1,1111", short: "11.1.1", build: "11.1.1", expected: false),
            DeliveryScenario(receipt: "3.32.721", tap: "3.32.721", short: "3.32", build: "721", expected: false),
            DeliveryScenario(receipt: "2.19.0,111", tap: "2.19.1,6046815158665216", short: "2.19.1", build: "2.19.1", expected: false),
            DeliveryScenario(receipt: "1.1.7", tap: "2.1.3,abcdef", short: "2.2.0", build: "2.2.0", expected: false),
            DeliveryScenario(receipt: "1.1.7", tap: "2.1.3,abcdef", short: "2.1.0", build: "2.1.0", expected: true),
            DeliveryScenario(receipt: "152.0.6", tap: "157.0", short: "150.0.2", build: "15026.5.6", expected: true)
        ]
        for scenario in scenarios {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let app = try makeInstallation(in: root, receiptVersion: scenario.receipt)
            try setApplicationVersion(scenario.short, at: app)
            try setBuildVersion(scenario.build, at: app)
            let service = makeService(in: root)
            await service.refresh()
            let (vm, _) = await makeSUT(
                casks: [makeAntinote(version: scenario.tap)], categories: makeCategories(), localHomebrew: service
            )
            let cask = try XCTUnwrap(vm.casks.first)
            vm.selectedSidebar = .library(.updates)
            service.setGreedyUpdates(true)
            let label = "\(scenario.short)/\(scenario.build) receipt \(scenario.receipt) tap \(scenario.tap)"
            XCTAssertEqual(service.installationSnapshot.installedCasks[cask.token]?.installedVersion, scenario.receipt, label)
            XCTAssertEqual(infoValues(for: cask, service: service)[String(localized: "Outdated")],
                           scenario.expected ? String(localized: "Yes") : String(localized: "No"), label)
            XCTAssertEqual(service.localState(for: cask).hasAvailableUpdate, scenario.expected, label)
            XCTAssertEqual(vm.updatesCount, scenario.expected ? 1 : 0, label)
        }
    }

    func test_greedy_off_lists_what_homebrew_reports() async throws {
        let scenarios = [
            GreedyScenario(homebrew: ["antinote"], short: "2.1.0", off: true, greedy: true),
            GreedyScenario(homebrew: [], short: "2.1.0", off: false, greedy: true),
            GreedyScenario(homebrew: nil, short: "2.1.0", off: false, greedy: true),
            GreedyScenario(homebrew: ["antinote"], short: "2.1.3", off: false, greedy: false),
            GreedyScenario(homebrew: [], pinned: true, short: "2.1.0", off: false, greedy: false),
            GreedyScenario(homebrew: ["antinote"], receipt: "2.1.3", short: "2.1.0", off: false, greedy: false),
            GreedyScenario(homebrew: ["antinote"], receiptApp: "Renamed.app", short: "2.1.0", off: true, greedy: true),
            GreedyScenario(homebrew: [], receiptApp: "Renamed.app", short: "2.1.0", off: false, greedy: false),
            GreedyScenario(homebrew: ["antinote"], appRemoved: true, short: "2.1.0", off: false, greedy: false)
        ]
        for (index, scenario) in scenarios.enumerated() {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let app = try makeInstallation(in: root, receiptVersion: scenario.receipt, receiptApp: scenario.receiptApp)
            try setApplicationVersion(scenario.short, at: app)
            if scenario.appRemoved { try FileManager.default.removeItem(at: app) }
            let service = makeService(
                in: root, homebrewOutdated: scenario.homebrew, pinned: scenario.pinned ? ["antinote"] : []
            )
            await service.refresh()
            await service.refreshHomebrewOutdated()
            let (vm, _) = await makeSUT(casks: [makeAntinote()], categories: makeCategories(), localHomebrew: service)
            let cask = try XCTUnwrap(vm.casks.first)
            vm.selectedSidebar = .library(.updates)
            for (greedy, expected) in [(false, scenario.off), (true, scenario.greedy)] {
                service.setGreedyUpdates(greedy)
                XCTAssertEqual(service.localState(for: cask).hasAvailableUpdate, expected, "scenario \(index) greedy \(greedy)")
                XCTAssertEqual(vm.updatesCount, expected ? 1 : 0, "scenario \(index) greedy \(greedy)")
            }
        }
    }

    func test_homebrew_is_asked_only_by_an_explicit_outdated_refresh() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeInstallation(in: root)
        var queries = 0
        let defaults = makeScratchDefaults("outdated-refresh-\(UUID().uuidString)")
        defaults.set(root.path, forKey: HomebrewLocator.customPrefixKey)
        let service = LocalHomebrewService(defaults: defaults) {
            $0.applicationDirectories = [root.appendingPathComponent("Applications")]
            $0.brewBinaryProvider = { nil }
            $0.brewVersionProvider = { "test" }
            $0.caskPlatformProvider = { CaskPlatform(tag: "arm64_sequoia") }
            $0.homebrewOutdatedProvider = { _ in
                queries += 1
                return HomebrewOutdatedReport(upgradable: ["antinote"], pinned: [])
            }
        }
        await service.refresh()
        await service.refresh()
        XCTAssertEqual(queries, 0)
        XCTAssertNil(service.homebrewOutdated)
        await service.refreshHomebrewOutdated()
        XCTAssertEqual(queries, 1)
        XCTAssertEqual(service.homebrewOutdated?.upgradable, ["antinote"])
    }

    func test_third_party_cask_updates_come_from_homebrew_and_survive_a_failed_check() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeInstallation(in: root)
        // The API catalog never lists another tap's cask; only Homebrew knows its current version.
        var answer = HomebrewOutdatedLoader.report(in: #"""
        {"formulae":[],"casks":[{"token":"antinote","tap":"acme/tap","name":["Antinote"],
          "homepage":"https://antinote.example","version":"2.1.3","outdated":true,"pinned":false,
          "deprecated":false,"disabled":false,"auto_updates":false}]}
        """#)
        var requests: [Bool] = []
        let defaults = makeScratchDefaults("outdated-third-party-\(UUID().uuidString)")
        defaults.set(root.path, forKey: HomebrewLocator.customPrefixKey)
        let service = LocalHomebrewService(defaults: defaults) {
            $0.applicationDirectories = [root.appendingPathComponent("Applications")]
            $0.brewBinaryProvider = { nil }
            $0.brewVersionProvider = { "test" }
            $0.caskPlatformProvider = { CaskPlatform(tag: "arm64_sequoia") }
            $0.homebrewOutdatedProvider = { userRequested in
                requests.append(userRequested)
                return answer
            }
        }
        await service.refresh()
        let (vm, _) = await makeSUT(casks: [Cask.preview(token: "other")], localHomebrew: service)
        vm.selectedSidebar = .library(.updates)
        XCTAssertEqual(vm.installedCasks.map(\.token), ["antinote"])
        XCTAssertEqual(vm.updatesCount, 0)

        await service.refreshHomebrewOutdated(userRequested: true)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["antinote"])

        answer = nil
        await service.refreshHomebrewOutdated()
        XCTAssertEqual(requests, [true, false])
        XCTAssertEqual(vm.updatesCount, 1, "a failed check keeps Homebrew's last answer")
    }

    func test_newer_app_evidence_overrides_a_cached_homebrew_listing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeInstallation(in: root)
        let service = makeService(in: root, homebrewOutdated: ["antinote"])
        await service.refresh()
        await service.refreshHomebrewOutdated()
        let (vm, _) = await makeSUT(casks: [makeAntinote()], categories: makeCategories(), localHomebrew: service)
        let cask = try XCTUnwrap(vm.casks.first)
        vm.selectedSidebar = .library(.updates)
        XCTAssertTrue(service.localState(for: cask).hasAvailableUpdate)

        try setApplicationVersion("2.1.3", at: app)
        await service.refresh()
        for greedy in [false, true] {
            service.setGreedyUpdates(greedy)
            XCTAssertFalse(service.localState(for: cask).hasAvailableUpdate, "self-updated, greedy \(greedy)")
            XCTAssertEqual(vm.updatesCount, 0, "self-updated, greedy \(greedy)")
        }

        try setApplicationVersion("2.2.0", at: app)
        let caskroom = root.appendingPathComponent("Caskroom/antinote")
        for parent in [caskroom, caskroom.appendingPathComponent(".metadata")] {
            try FileManager.default.moveItem(
                at: parent.appendingPathComponent("1.1.7"), to: parent.appendingPathComponent("2.2.0")
            )
        }
        await service.refresh()
        XCTAssertEqual(service.installationSnapshot.installedCasks[cask.token]?.installedVersion, "2.2.0")
        for greedy in [false, true] {
            service.setGreedyUpdates(greedy)
            XCTAssertFalse(service.localState(for: cask).hasAvailableUpdate, "upgraded past the catalog, greedy \(greedy)")
            XCTAssertEqual(vm.updatesCount, 0, "upgraded past the catalog, greedy \(greedy)")
        }
    }

    func test_ambiguous_identity_and_uncomparable_versions_keep_receipt_policy() async throws {
        let scenarios = ["wrong-id", "store", "duplicate", "missing-id", "multiple-apps", "build-only",
                         "beta", "beta-bundle", "manual-updates", "alias"]
        for scenario in scenarios {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let app = try makeInstallation(in: root)
            try setApplicationVersion("2.2.0", at: app)
            let version = scenario == "beta" ? "2.1.3beta" : "2.1.3"
            var cask = makeAntinote(version: version, autoUpdates: scenario != "manual-updates")
            try configure(scenario, app: app, cask: &cask)
            var casks = [cask]
            if scenario == "alias" {
                try makeInstallation(in: root, token: "antinote-alias")
                casks.append(makeAntinote(token: "antinote-alias"))
            }
            let service = makeService(in: root)
            await service.refresh()
            let (vm, _) = await makeSUT(
                casks: casks, categories: makeCategories(includeIdentity: scenario != "missing-id"),
                localHomebrew: service
            )
            let enriched = try XCTUnwrap(vm.casks.first { $0.token == "antinote" })
            service.setGreedyUpdates(true)
            let expectedVersion = scenario == "beta-bundle" ? "2.1.3beta"
                : ["beta", "manual-updates"].contains(scenario) ? "2.2.0" : "1.1.7"
            XCTAssertEqual(infoValues(for: enriched, service: service)[String(localized: "Installed Version")],
                           expectedVersion, scenario)
            XCTAssertTrue(service.localState(for: enriched).hasAvailableUpdate, scenario)
        }
    }

    private func configure(_ scenario: String, app: URL, cask: inout Cask) throws {
        switch scenario {
        case "wrong-id", "store", "duplicate":
            let directory = scenario == "duplicate"
                ? app.deletingLastPathComponent().appendingPathComponent("Duplicate")
                : app.deletingLastPathComponent()
            try makeApplicationBundle(
                in: directory, named: "Antinote.app",
                bundleIdentifier: scenario == "wrong-id" ? "com.example.unrelated" : "com.chabomakers.Antinote",
                macAppStoreReceipt: scenario == "store"
            )
        case "multiple-apps":
            cask.artifacts = [ArtifactStanza(keys: ["app"], appNames: ["Antinote.app", "Helper.app"])]
        case "beta-bundle":
            try setApplicationVersion("2.1.3beta", at: app)
        case "build-only":
            let url = app.appendingPathComponent("Contents/Info.plist")
            var info = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
            info.removeValue(forKey: "CFBundleShortVersionString")
            info["CFBundleVersion"] = "999"
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url)
        default:
            break
        }
    }

    @discardableResult
    private func makeInstallation(
        in root: URL, token: String = "antinote", receiptVersion: String = "1.1.7", receiptApp: String = "Antinote.app"
    ) throws -> URL {
        let app = try makeApplicationBundle(
            in: root.appendingPathComponent("Applications"), named: "Antinote.app",
            bundleIdentifier: "com.chabomakers.Antinote"
        )
        try setApplicationVersion("2.1.0", at: app)
        let caskroom = root.appendingPathComponent("Caskroom/\(token)")
        let version = caskroom.appendingPathComponent(receiptVersion)
        let metadata = caskroom.appendingPathComponent(".metadata")
        let caskfile = metadata.appendingPathComponent("\(receiptVersion)/20260718183151.778/Casks/\(token).json")
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caskfile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: version.appendingPathComponent("Antinote.app"), withDestinationURL: app)
        try Data("{}".utf8).write(to: caskfile)
        try Data(#"{"uninstall_artifacts":[{"app":["\#(receiptApp)"]}]}"#.utf8)
            .write(to: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
        return app
    }

    private func setBuildVersion(_ build: String?, at app: URL) throws {
        let url = app.appendingPathComponent("Contents/Info.plist")
        var info = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        info["CFBundleVersion"] = build
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url)
    }

    private func makeService(
        in root: URL, homebrewOutdated: Set<String>? = nil, pinned: Set<String> = []
    ) -> LocalHomebrewService {
        let defaults = makeScratchDefaults("app-version-\(UUID().uuidString)")
        defaults.set(root.path, forKey: HomebrewLocator.customPrefixKey)
        return LocalHomebrewService(defaults: defaults) {
            $0.applicationDirectories = [root.appendingPathComponent("Applications")]
            $0.brewBinaryProvider = { nil }
            $0.brewVersionProvider = { "test" }
            $0.caskPlatformProvider = { CaskPlatform(tag: "arm64_sequoia") }
            $0.homebrewOutdatedProvider = { _ in
                homebrewOutdated.map { HomebrewOutdatedReport(upgradable: $0, pinned: pinned) }
            }
        }
    }

    private func makeAntinote(token: String = "antinote", version: String = "2.1.3", autoUpdates: Bool = true) -> Cask {
        var cask = Cask.preview(token: token, version: version, autoUpdates: autoUpdates)
        cask.artifacts = [ArtifactStanza(keys: ["app"], appNames: ["Antinote.app"])]
        return cask
    }

    private func makeCategories(includeIdentity: Bool = true) -> CategoryService {
        let categories = CategoryService()
        categories.applyData(CaskCategoryData(
            version: 1, generatedDate: "2026-09-19", releaseTag: nil,
            categories: [:], tokenToCategory: [:], iconTokens: nil,
            appIdentities: includeIdentity ? ["antinote": [CaskAppIdentity(
                bundleName: "Antinote.app", bundleIdentifier: "com.chabomakers.Antinote"
            )]] : [:]
        ))
        return categories
    }

    private func infoValues(for cask: Cask, service: LocalHomebrewService) -> [String: String] {
        let rows = CaskInfoProjector.makeRows(from: CaskInfoProjectionInput(
            cask: cask, category: nil, downloadSize: nil,
            actionPresentation: service.actionPresentation(for: cask),
            externalVersion: service.externalAppVersion(for: cask),
            installationDates: service.installationDates(for: cask)
        ))
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.property, $0.value) })
    }
}
