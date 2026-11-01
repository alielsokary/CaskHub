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
                makeDetectedApplication(appName)
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

        render(ShelfSetupView(viewModel: vm)
            .environment(homebrew)
            .environment(ImageCacheService()), width: 1100, height: 600)
    }

    @MainActor
    func test_shelf_setup_view_renders_empty_state() async {
        let homebrew = makeHomebrew(
            defaults: makeScratchDefaults("adopt-render-empty"),
            externalApps: [:]
        )
        let (vm, _) = await makeSUT(casks: [], localHomebrew: homebrew)

        render(ShelfSetupView(viewModel: vm)
            .environment(homebrew)
            .environment(ImageCacheService()), width: 1100, height: 600)
    }

    @MainActor
    func test_make_import_plan_splits_installed_new_and_unknown_tokens() async {
        let homebrew = makeHomebrew(
            defaults: makeScratchDefaults("brewfile-plan"),
            externalApps: ["google-chrome": "Google Chrome.app"]
        )
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("google-chrome", appNames: ["Google Chrome.app"]),
                makeCask("raycast", appNames: ["Raycast.app"])
            ],
            localHomebrew: homebrew
        )

        let plan = ShelfSetupView(viewModel: vm).makeImportPlan(
            fileName: "~/Brewfile",
            tokens: ["homebrew/cask/google-chrome", "raycast", "mystery-app"]
        )

        XCTAssertEqual(
            plan.skippedEntries.map(\.token), ["homebrew/cask/google-chrome"],
            "externally installed app counts as present, even tap-qualified"
        )
        XCTAssertEqual(plan.newEntries.map(\.token), ["raycast", "mystery-app"])
        XCTAssertEqual(plan.listedCount, 3)
        XCTAssertEqual(plan.newEntries.first?.cask?.token, "raycast")
        XCTAssertNil(plan.newEntries.last?.cask, "unknown token keeps nil cask")
    }

    @MainActor
    func test_make_import_plan_skips_installed_tokens_and_lists_disabled_as_unavailable() async {
        let homebrew = makeHomebrew(defaults: makeScratchDefaults("brewfile-retired"), externalApps: [:])
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("raycast"),
                Cask.preview(token: "qbittorrent", disabled: true),
                Cask.preview(token: "chromium", disabled: true, disableReason: "fails_gatekeeper_check"),
                Cask.preview(token: "legacy-app", deprecated: true)
            ],
            localHomebrew: homebrew
        )
        for token in ["qbittorrent", "gone-app"] {
            updateInstalledCask(installation(token, version: "1.0"), in: homebrew)
        }

        let plan = ShelfSetupView(viewModel: vm).makeImportPlan(
            fileName: "~/Brewfile",
            tokens: ["qbittorrent", "gone-app", "chromium", "legacy-app", "raycast"]
        )

        XCTAssertEqual(plan.skippedEntries.map(\.token), ["qbittorrent", "gone-app"])
        XCTAssertEqual(plan.unavailableEntries.map(\.token), ["chromium"])
        XCTAssertEqual(plan.newEntries.map(\.token), ["legacy-app", "raycast"])
        XCTAssertEqual(plan.listedCount, 5)
        render(BrewfileImportSheet(plan: plan)
            .environment(homebrew)
            .environment(ImageCacheService()), width: 1100, height: 600)
    }

    @MainActor
    func test_brewfile_import_sheet_renders_every_phase() {
        let homebrew = makeHomebrew(
            defaults: makeScratchDefaults("brewfile-render"),
            externalApps: [:]
        )
        let plan = BrewfileImportPlan(
            fileName: "~/Brewfile",
            skippedEntries: [.init(token: "google-chrome", cask: makeCask("google-chrome"))],
            newEntries: [
                .init(token: "raycast", cask: makeCask("raycast")),
                .init(token: "mystery-app", cask: nil)
            ],
            unavailableEntries: []
        )
        let phases: [BrewfileImportPhase] = [
            .preview, .running(completedCount: 1), .done(failedCount: 0), .done(failedCount: 1)
        ]
        for phase in phases {
            render(BrewfileImportSheet(plan: plan, phase: phase)
                .environment(homebrew)
                .environment(ImageCacheService()), width: 1100, height: 600)
        }
        let nothingNew = BrewfileImportPlan(
            fileName: "~/Brewfile",
            skippedEntries: plan.skippedEntries,
            newEntries: [],
            unavailableEntries: []
        )
        render(BrewfileImportSheet(plan: nothingNew)
            .environment(homebrew)
            .environment(ImageCacheService()), width: 1100, height: 600)
    }

    @MainActor
    func test_ignore_picker_sheet_renders_adoptable_and_empty_states() async {
        let homebrew = makeHomebrew(
            defaults: makeScratchDefaults("adopt-picker-render"),
            externalApps: [
                "google-chrome": "Google Chrome.app",
                "slack": "Slack.app"
            ]
        )
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("google-chrome", appNames: ["Google Chrome.app"]),
                makeCask("slack", appNames: ["Slack.app"])
            ],
            localHomebrew: homebrew
        )

        render(AdoptIgnorePickerSheet(viewModel: vm)
            .environment(homebrew)
            .environment(ImageCacheService()), width: 1100, height: 600)

        homebrew.setAdoptIgnored("google-chrome", true)
        homebrew.setAdoptIgnored("slack", true)
        XCTAssertTrue(vm.adoptableCasks.isEmpty)

        render(AdoptIgnorePickerSheet(viewModel: vm)
            .environment(homebrew)
            .environment(ImageCacheService()), width: 1100, height: 600)
    }

    @MainActor
    func test_ignored_casks_sort_newest_first_with_token_tiebreak() async {
        let homebrew = makeHomebrew(
            defaults: makeScratchDefaults("adopt-sort"),
            externalApps: [
                "google-chrome": "Google Chrome.app",
                "slack": "Slack.app"
            ]
        )
        let (vm, _) = await makeSUT(
            casks: [
                makeCask("google-chrome", appNames: ["Google Chrome.app"]),
                makeCask("slack", appNames: ["Slack.app"])
            ],
            localHomebrew: homebrew
        )
        homebrew.setAdoptIgnored("slack", true)
        homebrew.setAdoptIgnored("google-chrome", true)

        // chrome wins by date (ignored later) or by token on an equal-date tie.
        XCTAssertEqual(vm.adoptIgnoredCasks.map(\.token), ["google-chrome", "slack"])
    }

    @MainActor
    func test_page_chrome_renders() {
        render(CountBadge(count: 2), width: 1100, height: 600)
    }

    @MainActor
    func test_health_and_shelf_buttons_fit_compact_pages_in_both_styles() async {
        let originalStyle = AppStyle.current
        defer { AppStyle.current = originalStyle }
        let homebrew = makeHomebrew(defaults: makeScratchDefaults("utility-buttons"), externalApps: ["slack": "Slack.app"])
        let (vm, _) = await makeSUT(
            casks: [makeCask("slack", appNames: ["Slack.app"])], localHomebrew: homebrew
        )
        homebrew.setAdoptIgnored("slack", true)
        let probe = RecordingMaintenanceProbe()
        probe.directorySizes = ["Homebrew": 1_000, "icons": 2_000]
        let model = makeMaintenanceModel(probe: probe)
        await model.refreshDisk()
        let imageCache = ImageCacheService()
        for style in AppStyle.allCases {
            AppStyle.current = style
            let pages = [
                AnyView(ShelfSetupView(viewModel: vm).environment(homebrew).environment(imageCache)),
                AnyView(MaintenanceView(model: model).environment(imageCache))
            ]
            for (index, page) in pages.enumerated() {
                for width: CGFloat in [754, 1100] {
                    let host = NSHostingController(rootView: page)
                    let size = host.sizeThatFits(in: CGSize(width: width, height: 700))
                    XCTAssertLessThanOrEqual(size.width, width, "\(style) page \(index) at \(width)")
                }
            }
        }
    }

    @MainActor
    func test_content_view_renders_utility_pages() async {
        let categories = CategoryService()
        let homebrew = makeHomebrew(
            defaults: makeScratchDefaults("adopt-content-render"),
            externalApps: ["slack": "Slack.app"]
        )
        let api = MockBrewAPIClient()
        api.casks = [makeCask("slack", appNames: ["Slack.app"])]
        let vm = makeViewModel(api: api, categories: categories, localHomebrew: homebrew)
        await vm.fetchCasks()
        vm.selectedSidebar = .shelfSetup

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(viewModel: vm)
            .environment(categories)
            .environment(homebrew)
            .environment(ImageCacheService())
            .environment(MaintenanceViewModel(
                localHomebrew: homebrew,
                catalog: vm,
                clearImageCache: {},
                probe: RecordingMaintenanceProbe(),
                defaults: makeScratchDefaults("maintenance-content-render")
            )))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        vm.selectedSidebar = .maintenance
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        addTeardownBlock { @MainActor in
            window.contentView = NSView()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.close()
        }
    }
}
