//
//  HomebrewAppVersionTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 19/09/2026.
//  Copyright © 2026 BuildingLink. All rights reserved.
//

@testable import CaskHub
import XCTest

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
            (("4.2.19", nil), true),
            (("4.2.19", "317beta"), true),
            (("4.2.19", ""), true)
        ]
        for ((release, build), expectedOutdated) in scenarios {
            try setApplicationVersion(release, at: app)
            let plistURL = app.appendingPathComponent("Contents/Info.plist")
            var info = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any]
            )
            info["CFBundleVersion"] = build
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plistURL)
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

    func test_ambiguous_identity_and_uncomparable_versions_keep_receipt_policy() async throws {
        let scenarios = ["wrong-id", "store", "duplicate", "missing-id", "multiple-apps", "build-only",
                         "composite", "beta", "beta-bundle", "manual-updates", "alias"]
        for scenario in scenarios {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let app = try makeInstallation(in: root)
            try setApplicationVersion("2.2.0", at: app)
            let version = scenario == "composite" ? "2.1.3,abcdef" : scenario == "beta" ? "2.1.3beta" : "2.1.3"
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
                : ["composite", "beta", "manual-updates"].contains(scenario) ? "2.2.0" : "1.1.7"
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
    private func makeInstallation(in root: URL, token: String = "antinote") throws -> URL {
        let app = try makeApplicationBundle(
            in: root.appendingPathComponent("Applications"), named: "Antinote.app",
            bundleIdentifier: "com.chabomakers.Antinote"
        )
        try setApplicationVersion("2.1.0", at: app)
        let caskroom = root.appendingPathComponent("Caskroom/\(token)")
        let version = caskroom.appendingPathComponent("1.1.7")
        let metadata = caskroom.appendingPathComponent(".metadata")
        let caskfile = metadata.appendingPathComponent("1.1.7/20260718183151.778/Casks/\(token).json")
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caskfile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: version.appendingPathComponent("Antinote.app"), withDestinationURL: app)
        try Data("{}".utf8).write(to: caskfile)
        try Data(#"{"uninstall_artifacts":[{"app":["Antinote.app"]}]}"#.utf8)
            .write(to: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
        return app
    }

    private func makeService(in root: URL) -> LocalHomebrewService {
        let defaults = makeScratchDefaults("app-version-\(UUID().uuidString)")
        defaults.set(root.path, forKey: HomebrewLocator.customPrefixKey)
        return LocalHomebrewService(defaults: defaults) {
            $0.applicationDirectories = [root.appendingPathComponent("Applications")]
            $0.brewBinaryProvider = { nil }
            $0.brewVersionProvider = { "test" }
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
