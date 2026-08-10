//
//  ShelfSetupViewTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 10/08/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

final class ShelfSetupViewTests: XCTestCase {
    @MainActor
    private func makeHomebrew(
        defaults: UserDefaults,
        externalApps: [String: String]
    ) -> LocalHomebrewService {
        let homebrew = LocalHomebrewService(defaults: defaults) {
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
        }
        updateInstallationSnapshot(of: homebrew) { fixture in
            fixture.externalAppNames = Set(externalApps.values)
            fixture.externalApplicationOwners = externalApps.mapValues { appName in
                DetectedApplication(
                    url: URL(fileURLWithPath: "/Applications/\(appName)"),
                    bundleName: appName,
                    bundleIdentifier: "com.example.\(appName)",
                    isMacAppStore: false,
                    isDirectlyInApplicationDirectory: true
                )
            }
        }
        return homebrew
    }

    @MainActor
    func test_ignoring_a_token_hides_it_from_adopt_and_persists() async {
        let defaults = makeScratchDefaults("adopt-ignore")
        let homebrew = makeHomebrew(defaults: defaults, externalApps: [
            "google-chrome": "Google Chrome.app",
            "slack": "Slack.app"
        ])
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("google-chrome", appNames: ["Google Chrome.app"]),
                makeCask("slack", appNames: ["Slack.app"])
            ],
            localHomebrew: homebrew
        )
        vm.selectedSidebar = .library(.adopt)
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["google-chrome", "slack"])

        homebrew.setAdoptIgnored("google-chrome", true)

        XCTAssertEqual(vm.adoptableCasks.map(\.token), ["slack"])
        XCTAssertEqual(vm.filteredCasks.map(\.token), ["slack"])
        XCTAssertEqual(vm.adoptIgnoredCasks.map(\.token), ["google-chrome"])

        let relaunched = LocalHomebrewService(defaults: defaults)
        XCTAssertEqual(
            Set(relaunched.adoptIgnoredDates.keys), ["google-chrome"],
            "ignore list survives relaunch"
        )
    }

    @MainActor
    func test_restoring_a_token_returns_it_to_adopt() async {
        let defaults = makeScratchDefaults("adopt-restore")
        let homebrew = makeHomebrew(defaults: defaults, externalApps: ["slack": "Slack.app"])
        let (vm, _) = await makeSUT(
            casks: [makeCask("slack", appNames: ["Slack.app"])],
            localHomebrew: homebrew
        )
        homebrew.setAdoptIgnored("slack", true)
        XCTAssertTrue(vm.adoptableCasks.isEmpty)

        homebrew.setAdoptIgnored("slack", false)

        XCTAssertEqual(vm.adoptableCasks.map(\.token), ["slack"])
        XCTAssertTrue(vm.adoptIgnoredCasks.isEmpty)
        XCTAssertTrue(LocalHomebrewService(defaults: defaults).adoptIgnoredDates.isEmpty)
    }

    @MainActor
    func test_shelf_setup_and_maintenance_pages_list_no_casks() async {
        let (vm, _) = await makeSUT(casks: [makeCask("slack")])

        vm.selectedSidebar = .shelfSetup
        XCTAssertTrue(vm.filteredCasks.isEmpty)

        vm.selectedSidebar = .maintenance
        XCTAssertTrue(vm.filteredCasks.isEmpty)
    }

    @MainActor
    func test_shelf_setup_view_renders_ignored_rows() async {
        let homebrew = makeHomebrew(
            defaults: makeScratchDefaults("adopt-render"),
            externalApps: ["slack": "Slack.app"]
        )
        let (vm, _) = await makeSUT(
            casks: [makeCask("slack", appNames: ["Slack.app"])],
            localHomebrew: homebrew
        )
        homebrew.setAdoptIgnored("slack", true)

        let view = ShelfSetupView(viewModel: vm)
            .environment(homebrew)
            .environment(ImageCacheService())
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 600)
        hosting.layoutSubtreeIfNeeded()
    }
}
