//
//  MaintenanceViewTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 19/08/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

final class MaintenanceViewTests: XCTestCase {
    @MainActor
    private func makeModel(
        probe: RecordingMaintenanceProbe? = nil,
        function: String = #function
    ) -> MaintenanceViewModel {
        let probe = probe ?? RecordingMaintenanceProbe()
        let defaults = makeScratchDefaults(function)
        let homebrew = LocalHomebrewService(defaults: defaults) {
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/opt/homebrew/bin/brew") }
            $0.brewVersionProvider = { "4.6.15" }
        }
        let catalog = makeViewModel(api: MockBrewAPIClient(), localHomebrew: homebrew)
        return MaintenanceViewModel(
            localHomebrew: homebrew,
            catalog: catalog,
            clearImageCache: {},
            probe: probe,
            defaults: defaults
        )
    }

    @MainActor
    func test_page_renders_before_first_checkup() {
        render(MaintenanceView(model: makeModel()))
    }

    @MainActor
    func test_disk_card_renders_loading_state_before_first_scan() {
        render(MaintenanceDiskCard(model: makeModel()))
    }

    @MainActor
    func test_page_renders_checkup_results() async {
        let probe = RecordingMaintenanceProbe()
        probe.resultsByFirstArgument = [
            "-p": BrewProbeResult(exitCode: 0, output: "/Library/Developer/CommandLineTools\n"),
            "doctor": BrewProbeResult(exitCode: 1, output: """
            Warning: Broken symlinks were found. Remove them with `brew cleanup`:
              /opt/homebrew/lib/libfoo.dylib
            """)
        ]
        let model = makeModel(probe: probe)
        await model.runCheckup()

        render(MaintenanceView(model: model))
    }

    @MainActor
    func test_disk_card_renders_sizes_and_expanded_rows() async {
        let probe = RecordingMaintenanceProbe()
        probe.resultsByFirstArgument = [
            "cleanup": BrewProbeResult(exitCode: 0, output: """
            Would remove: /opt/homebrew/Caskroom/figma/124.7 (3 files, 200MB)
            """),
            "autoremove": BrewProbeResult(exitCode: 0, output: """
            ==> Would autoremove 1 unneeded formulae:
            libyaml
            """)
        ]
        probe.directorySizes = ["Homebrew": 1_000, "icons": 2_000, "libyaml": 300]
        let model = makeModel(probe: probe)
        await model.refreshDisk()
        model.expandedRows = [.cache, .imageCache]

        render(MaintenanceDiskCard(model: model))
    }

    @MainActor
    func test_disk_card_renders_done_and_failed_rows() async {
        let probe = RecordingMaintenanceProbe()
        probe.resultsByFirstArgument = [
            "autoremove": BrewProbeResult(exitCode: 1, output: "Error: nope")
        ]
        let model = makeModel(probe: probe)
        await model.clean(.imageCache)
        await model.clean(.orphans)

        render(MaintenanceDiskCard(model: model))
    }

    @MainActor
    private func render(_ view: some View) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 700)
        hosting.layoutSubtreeIfNeeded()
    }
}
