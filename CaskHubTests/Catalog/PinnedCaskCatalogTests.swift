//
//  PinnedCaskCatalogTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 15/11/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class PinnedCaskCatalogTests: XCTestCase {
    private func makeViewModel(
        casks: [Cask],
        installed: [LocalCaskInstallation],
        pins: [String: String],
        verifiedZombies: Set<String> = []
    ) async -> CaskCatalogViewModel {
        let homebrew = LocalHomebrewService(defaults: makeScratchDefaults("pins-\(UUID().uuidString)")) {
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
        }
        let (vm, _) = await makeSUT(casks: casks, localHomebrew: homebrew)
        for installation in installed {
            updateInstalledCask(installation, in: homebrew)
        }
        updateInstallationSnapshot(of: homebrew) {
            $0.pinnedVersions = pins
            $0.installationIndex = CaskInstallationIndex(
                catalogTokens: Set(casks.map(\.token)), macAppStoreApplications: [:], externalCLIPaths: [:],
                homebrewApplications: [:], verifiedZombieTokens: verifiedZombies
            )
        }
        return vm
    }

    private func installation(_ token: String, tap: String = "homebrew/cask", isZombie: Bool = false) -> LocalCaskInstallation {
        LocalCaskInstallation(
            token: token, installedVersion: "1.0", installedAt: nil,
            appBundleNames: [], isZombie: isZombie, tap: tap
        )
    }

    func test_pinned_casks_list_pins_sorted_by_name() async {
        let vm = await makeViewModel(
            casks: [makeCask("zed", name: "Zed"), makeCask("alfred", name: "Alfred"), makeCask("onyx", name: "OnyX")],
            installed: ["zed", "alfred", "onyx"].map { installation($0) },
            pins: ["zed": "1.0", "alfred": "1.0"]
        )

        XCTAssertEqual(vm.pinnedCasks.map(\.token), ["alfred", "zed"])
    }

    func test_pinned_tap_and_receipt_only_casks_are_listed() async {
        let vm = await makeViewModel(
            casks: [makeCask("zed", name: "Zed")],
            installed: [installation("zed"), installation("widget", tap: "acme/tools")],
            pins: ["zed": "1.0", "widget": "2.0"]
        )

        let widget = vm.pinnedCasks.first { $0.token == "widget" }
        XCTAssertEqual(vm.pinnedCasks.map(\.token), ["widget", "zed"])
        XCTAssertEqual(widget?.reference, "acme/tools/widget")
        XCTAssertEqual(widget?.displayName, "widget")
    }

    func test_pinnable_casks_exclude_pinned_and_zombie_casks() async {
        let vm = await makeViewModel(
            casks: [
                makeCask("zed", name: "Zed"), makeCask("alfred", name: "Alfred"),
                makeCask("onyx", name: "OnyX", appNames: ["OnyX.app"])
            ],
            installed: [installation("zed"), installation("alfred"), installation("onyx", isZombie: true)],
            pins: ["zed": "1.0"],
            verifiedZombies: ["onyx"]
        )

        XCTAssertEqual(vm.pinnableCasks(matching: "").map(\.token), ["alfred"])
    }

    func test_pinnable_filter_matches_name_or_token_ignoring_case_and_accents() async {
        let casks = [
            makeCask("firefox", name: "Firefox"),
            makeCask("cafe-app", name: "Café"),
            makeCask("visual-studio-code", name: "Code")
        ]
        let vm = await makeViewModel(casks: casks, installed: casks.map { installation($0.token) }, pins: [:])

        XCTAssertEqual(vm.pinnableCasks(matching: "FIRE").map(\.token), ["firefox"])
        XCTAssertEqual(vm.pinnableCasks(matching: "cafe").map(\.token), ["cafe-app"])
        XCTAssertEqual(vm.pinnableCasks(matching: "visual-studio").map(\.token), ["visual-studio-code"])
        XCTAssertEqual(vm.pinnableCasks(matching: "  ").map(\.token), ["cafe-app", "visual-studio-code", "firefox"])
        XCTAssertTrue(vm.pinnableCasks(matching: "zzz").isEmpty)
    }
}
