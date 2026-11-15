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

        render(ShelfSetupView(viewModel: vm, picker: .constant(nil))
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

        render(ShelfSetupView(viewModel: vm, picker: .constant(nil))
            .environment(homebrew)
            .environment(ImageCacheService()), width: 1100, height: 600)
    }

    @MainActor
    private func makePinnedSUT(brewVersion: String? = "test") async -> CaskCatalogViewModel {
        let homebrew = LocalHomebrewService(defaults: makeScratchDefaults("pin-render-\(UUID().uuidString)")) {
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
            $0.brewBinaryProvider = { nil }
            $0.caskPlatformProvider = { nil }
            $0.brewVersionProvider = { brewVersion }
        }
        await homebrew.refresh()
        let selfUpdating = Cask.preview(token: "onyx", name: "OnyX", autoUpdates: true)
        let (vm, _) = await makeSUT(casks: [makeCask("zed", name: "Zed"), selfUpdating], localHomebrew: homebrew)
        for token in ["zed", "onyx"] {
            updateInstalledCask(LocalCaskInstallation(
                token: token, installedVersion: "1.0", installedAt: nil, appBundleNames: [], tap: "homebrew/cask"
            ), in: homebrew)
        }
        return vm
    }

    @MainActor
    func test_pinned_card_labels_pins_and_self_updating_casks() async {
        let vm = await makePinnedSUT()
        updateInstallationSnapshot(of: vm.localHomebrew) { $0.pinnedVersions = ["zed": "1.0", "onyx": "2.1,77"] }
        let card = PinnedUpdatesCard(viewModel: vm, picker: .constant(nil))

        XCTAssertEqual(vm.pinnedCasks.map(\.token), ["onyx", "zed"])
        XCTAssertEqual(card.pinnedLabel(for: vm.pinnedCasks[1]), "pinned at 1.0")
        XCTAssertEqual(card.pinnedLabel(for: vm.pinnedCasks[0]), "pinned at 2.1,77")
        XCTAssertTrue(card.showsSelfUpdatingHint(vm.pinnedCasks[0]))
        XCTAssertFalse(card.showsSelfUpdatingHint(vm.pinnedCasks[1]))
        XCTAssertTrue(card.canPin)
        vm.localHomebrew.operationStore.send(.fail(CaskOperationFailure(kind: .brewCommand, message: "failed")), for: "zed")
        XCTAssertFalse(card.isBusy(vm.pinnedCasks[1]))
        vm.localHomebrew.operationStore.send(.enqueue(.updating), for: "onyx")
        XCTAssertTrue(card.isBusy(vm.pinnedCasks[0]))
        render(ShelfSetupView(viewModel: vm, picker: .constant(nil))
            .environment(vm.localHomebrew)
            .environment(ImageCacheService()), width: 1100, height: 800)
    }

    @MainActor
    func test_pinned_card_renders_empty_state() async {
        let vm = await makePinnedSUT()

        XCTAssertTrue(vm.pinnedCasks.isEmpty)
        XCTAssertEqual(String(localized: .shelfSetupPinEmpty), "No pinned apps.")
        XCTAssertEqual(String(localized: .shelfSetupPinAddButton), "Pin an app")
        render(PinnedUpdatesCard(viewModel: vm, picker: .constant(nil)).environment(vm.localHomebrew), width: 1100, height: 300)
    }

    @MainActor
    func test_pinned_card_hides_pinning_on_old_homebrew() async {
        let vm = await makePinnedSUT(brewVersion: "5.1.11")

        XCTAssertFalse(PinnedUpdatesCard(viewModel: vm, picker: .constant(nil)).canPin)
        render(PinnedUpdatesCard(viewModel: vm, picker: .constant(nil)).environment(vm.localHomebrew), width: 1100, height: 300)
    }

    @MainActor
    func test_pin_picker_messages_and_render() async {
        let vm = await makePinnedSUT()

        updateInstallationSnapshot(of: vm.localHomebrew) {
            $0.installationIndex = CaskInstallationIndex(
                catalogTokens: ["zed", "onyx"], macAppStoreApplications: [:], externalCLIPaths: [:],
                homebrewApplications: ["onyx": makeDetectedApplication("OnyX.app", version: "2.0.1")]
            )
        }
        let picker = PinPickerSheet(viewModel: vm)
        let casks = vm.pinnableCasks(matching: "")

        XCTAssertEqual(PinPickerSheet.emptyMessage(query: ""), "No installed apps to pin.")
        XCTAssertEqual(PinPickerSheet.emptyMessage(query: "zzz"), "No matching apps.")
        XCTAssertEqual(casks.map(\.token), ["onyx", "zed"])
        XCTAssertEqual(picker.installedVersion(for: casks[0]), "2.0.1")
        XCTAssertEqual(picker.installedVersion(for: casks[1]), "1.0")
        XCTAssertEqual(ShelfSetupPicker.pin.id, "pin")
        XCTAssertEqual(ShelfSetupPicker.adoptIgnore.id, "adoptIgnore")
        render(PinPickerSheet(viewModel: vm)
            .environment(vm.localHomebrew)
            .environment(ImageCacheService()), width: 400, height: 500)
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

        let plan = ShelfSetupView(viewModel: vm, picker: .constant(nil)).makeImportPlan(
            fileName: "~/Brewfile",
            tokens: ["homebrew/cask/google-chrome", "raycast", "mystery-app"],
            taps: []
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

        let plan = ShelfSetupView(viewModel: vm, picker: .constant(nil)).makeImportPlan(
            fileName: "~/Brewfile",
            tokens: ["qbittorrent", "gone-app", "chromium", "legacy-app", "raycast"],
            taps: []
        )

        XCTAssertEqual(plan.skippedEntries.map(\.token), ["qbittorrent", "gone-app"])
        XCTAssertEqual(plan.unavailableEntries.map(\.token), ["chromium"])
        XCTAssertEqual(plan.newEntries.map(\.token), ["legacy-app", "raycast"])
        XCTAssertEqual(plan.listedCount, 5)
        render(BrewfileImportSheet(plan: plan, addTap: { _ in })
            .environment(homebrew)
            .environment(ImageCacheService()), width: 1100, height: 600)
    }

    @MainActor
    func test_import_plan_keeps_tap_casks_apart_from_official_twins() async {
        let homebrew = makeHomebrew(defaults: makeScratchDefaults("brewfile-taps"), externalApps: [:])
        let (vm, _) = await makeSUT(casks: [makeCask("sill")], localHomebrew: homebrew)
        homebrew.tapIndex = TapIndex(
            taps: [TapSummary(
                name: "hashicorp/tap", remote: nil, official: false, trusted: false, customRemote: false,
                caskTokens: [], formulaNames: [], caskFiles: []
            )],
            casks: [],
            trust: TapTrust(taps: [], casks: [])
        )

        let plan = ShelfSetupView(viewModel: vm, picker: .constant(nil)).makeImportPlan(
            fileName: "~/Brewfile",
            tokens: ["sill", "saffsanity/sill/sill"],
            taps: [
                TapAddRequest(tapName: "hashicorp/tap", remoteURL: nil, caskToken: nil),
                TapAddRequest(tapName: "user/casks", remoteURL: URL(string: "https://github.com/user/casks"), caskToken: nil)
            ]
        )

        XCTAssertEqual(plan.newEntries.map(\.reference), ["sill", "saffsanity/sill/sill"])
        XCTAssertNotNil(plan.newEntries.first?.cask)
        XCTAssertNil(plan.newEntries.last?.cask, "never resolves to the official twin")
        XCTAssertEqual(plan.tapsToAdd.map(\.tapName), ["user/casks", "saffsanity/sill"])
        render(BrewfileImportSheet(plan: plan, addTap: { _ in })
            .environment(homebrew)
            .environment(ImageCacheService()), width: 1100, height: 600)
    }

    @MainActor
    func test_import_plan_skips_casks_whose_twin_is_installed_and_ignores_case_tricks() async {
        let homebrew = makeHomebrew(defaults: makeScratchDefaults("brewfile-twins"), externalApps: [:])
        let (vm, _) = await makeSUT(casks: [makeCask("foo")], localHomebrew: homebrew)
        updateInstalledCask(
            LocalCaskInstallation(token: "foo", installedVersion: "1.0", installedAt: nil, appBundleNames: [], tap: "user/tap"),
            in: homebrew
        )

        let plan = ShelfSetupView(viewModel: vm, picker: .constant(nil)).makeImportPlan(
            fileName: "~/Brewfile", tokens: ["foo", "Homebrew/Cask/bar"], taps: []
        )

        XCTAssertEqual(plan.skippedEntries.map(\.token), ["foo"])
        XCTAssertEqual(plan.newEntries.map(\.reference), ["bar"])
        XCTAssertTrue(plan.tapsToAdd.isEmpty)
    }

    @MainActor
    func test_import_sheet_names_a_custom_tap_remote() {
        let plan = BrewfileImportPlan(
            fileName: "~/Brewfile", skippedEntries: [], newEntries: [], unavailableEntries: [],
            tapsToAdd: [
                TapAddRequest(tapName: "hashicorp/tap", remoteURL: URL(string: "https://evil.example/x"), caskToken: nil),
                TapAddRequest(tapName: "user/plain", remoteURL: nil, caskToken: nil)
            ]
        )

        XCTAssertEqual(plan.tapsToAddText, "hashicorp/tap (from evil.example/x), user/plain")
    }

    @MainActor
    func test_import_adds_taps_before_installing_without_prompting() async {
        let plan = BrewfileImportPlan(
            fileName: "~/Brewfile", skippedEntries: [],
            newEntries: [.init(token: "saffsanity/sill/sill", cask: nil), .init(token: "figma", cask: nil)],
            unavailableEntries: [],
            tapsToAdd: [TapAddRequest(tapName: "saffsanity/sill", remoteURL: nil, caskToken: nil)]
        )
        var events: [String] = []

        let failed = await plan.run(
            selected: plan.newEntries,
            addTap: { events.append("tap \($0.tapName)") },
            installAll: { references in
                events.append("install \(references.joined(separator: ","))")
                return 0
            }
        )

        XCTAssertEqual(failed, 0)
        XCTAssertEqual(events, ["tap saffsanity/sill", "install saffsanity/sill/sill,figma"])
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
            unavailableEntries: [],
            tapsToAdd: []
        )
        let phases: [BrewfileImportPhase] = [
            .preview, .running(completedCount: 1), .done(failedCount: 0), .done(failedCount: 1)
        ]
        for phase in phases {
            render(BrewfileImportSheet(plan: plan, phase: phase, addTap: { _ in })
                .environment(homebrew)
                .environment(ImageCacheService()), width: 1100, height: 600)
        }
        let nothingNew = BrewfileImportPlan(
            fileName: "~/Brewfile",
            skippedEntries: plan.skippedEntries,
            newEntries: [],
            unavailableEntries: [],
            tapsToAdd: []
        )
        render(BrewfileImportSheet(plan: nothingNew, addTap: { _ in })
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
                AnyView(ShelfSetupView(viewModel: vm, picker: .constant(nil)).environment(homebrew).environment(imageCache)),
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
