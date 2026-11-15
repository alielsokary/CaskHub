//
//  PinnedUpdatesCardTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 15/11/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

final class PinnedUpdatesCardTests: XCTestCase {
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
        XCTAssertEqual(card.pinnedLabel(for: vm.pinnedCasks[0]), "pinned at 2.1")
        XCTAssertEqual(
            card.selfUpdatingHelp(for: vm.pinnedCasks[0]),
            "onyx has `auto_updates true` and may update itself outside Homebrew despite being pinned."
        )
        XCTAssertNil(card.selfUpdatingHelp(for: vm.pinnedCasks[1]))
        XCTAssertEqual(PinnedUpdatesCard.selfUpdatingSymbol, LibraryItem.updates.icon)
        XCTAssertFalse(card.isPinChanging(vm.pinnedCasks[1]))
        vm.localHomebrew.pinChangesInFlight.insert(vm.pinnedCasks[1].reference)
        XCTAssertTrue(card.isPinChanging(vm.pinnedCasks[1]))
        XCTAssertFalse(card.isBlocked(vm.pinnedCasks[1]), "a running pin shows its spinner, not the dimmed state")
        render(PinnedUpdatesCard(viewModel: vm, picker: .constant(nil)).environment(vm.localHomebrew), width: 1100, height: 400)
        vm.localHomebrew.pinChangesInFlight.removeAll()
        XCTAssertTrue(card.canPin)
        vm.localHomebrew.operationStore.send(.fail(CaskOperationFailure(kind: .brewCommand, message: "failed")), for: "zed")
        XCTAssertFalse(card.isBusy(vm.pinnedCasks[1]))
        vm.localHomebrew.operationStore.send(.enqueue(.updating), for: "onyx")
        XCTAssertTrue(card.isBusy(vm.pinnedCasks[0]))
        XCTAssertTrue(card.isBlocked(vm.pinnedCasks[0]))
        render(ShelfSetupView(viewModel: vm)
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
        XCTAssertEqual(picker.installedVersion(for: casks[0]), "1.0", "Homebrew's version, the one a pin keeps")
        XCTAssertEqual(picker.installedVersion(for: casks[1]), "1.0")
        updateInstalledCask(LocalCaskInstallation(
            token: "zed", installedVersion: "2026.1.2.10,quail2,AI-261", installedAt: nil, appBundleNames: [], tap: "homebrew/cask"
        ), in: vm.localHomebrew)
        XCTAssertEqual(picker.installedVersion(for: casks[1]), "2026.1.2.10")
        XCTAssertEqual(ShelfSetupPicker.pin.id, "pin")
        XCTAssertEqual(ShelfSetupPicker.adoptIgnore.id, "adoptIgnore")
        render(PinPickerSheet(viewModel: vm)
            .environment(vm.localHomebrew)
            .environment(ImageCacheService()), width: 400, height: 500)
    }
}
