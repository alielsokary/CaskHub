//
//  MaintenanceViewModelTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 19/08/2026.
//

@testable import CaskHub
import XCTest

final class MaintenanceViewModelTests: XCTestCase {
    // MARK: - Checkup

    @MainActor
    func test_checkup_collects_doctor_warnings_and_persists() async {
        let probe = RecordingMaintenanceProbe()
        probe.resultsByFirstArgument = [
            "-p": BrewProbeResult(exitCode: 0, output: "/Library/Developer/CommandLineTools\n"),
            "doctor": BrewProbeResult(exitCode: 1, output: """
            Warning: Broken symlinks were found. Remove them with `brew cleanup`:
              /opt/homebrew/lib/libfoo.dylib

            Warning: Unbrewed dylibs were found in /usr/local/lib.
            """)
        ]
        let defaults = makeScratchDefaults("checkup-warnings")
        let model = makeMaintenanceModel(probe: probe, defaults: defaults)

        await model.runCheckup()

        XCTAssertEqual(model.checks.count, 4)
        XCTAssertEqual(model.checks[0].status, .pass)
        XCTAssertEqual(model.checks[1].status, .pass)
        XCTAssertEqual(model.advisoryCount, 2)
        XCTAssertTrue(model.advisoriesExpanded)
        XCTAssertNotNil(model.lastChecked)
        XCTAssertNotNil(model.topBarSummary)

        let relaunched = makeMaintenanceModel(defaults: defaults)
        XCTAssertEqual(relaunched.advisoryCount, 2)
        XCTAssertNotNil(relaunched.lastChecked)
    }

    @MainActor
    func test_checkup_all_clear_reports_zero_advisories() async {
        let probe = RecordingMaintenanceProbe()
        probe.resultsByFirstArgument = [
            "-p": BrewProbeResult(exitCode: 0, output: "/Library/Developer/CommandLineTools\n"),
            "doctor": BrewProbeResult(exitCode: 0, output: "Your system is ready to brew.\n")
        ]
        let model = makeMaintenanceModel(probe: probe)

        await model.runCheckup()

        XCTAssertEqual(model.advisoryCount, 0)
        XCTAssertEqual(model.checks.count, 2)
        XCTAssertTrue(model.checks.allSatisfy { $0.status == .pass })
    }

    @MainActor
    func test_checkup_flags_missing_command_line_tools() async {
        let probe = RecordingMaintenanceProbe()
        probe.resultsByFirstArgument = [
            "-p": BrewProbeResult(exitCode: 2, output: "xcode-select: error: unable to get active developer directory\n"),
            "doctor": BrewProbeResult(exitCode: 0, output: "Your system is ready to brew.\n")
        ]
        let model = makeMaintenanceModel(probe: probe)

        await model.runCheckup()

        XCTAssertEqual(model.checks[1].status, .advisory)
        XCTAssertEqual(model.advisoryCount, 1)
    }

    @MainActor
    func test_checkup_runs_doctor_with_brew_path_first() async {
        let probe = RecordingMaintenanceProbe()
        let model = makeMaintenanceModel(probe: probe)

        await model.runCheckup()

        let doctorIndex = probe.commands.firstIndex(of: ["brew", "doctor"])
        XCTAssertNotNil(doctorIndex)
        let path = doctorIndex.flatMap { probe.environments[$0]?["PATH"] }
        XCTAssertEqual(path?.hasPrefix("/opt/homebrew/bin:/opt/homebrew/sbin:"), true)
    }

    // MARK: - Disk Scan

    @MainActor
    func test_refreshDisk_populates_sizes_from_probes() async {
        let probe = RecordingMaintenanceProbe()
        probe.resultsByFirstArgument = [
            "cleanup": BrewProbeResult(exitCode: 0, output: """
            Would remove: /opt/homebrew/Caskroom/figma/124.7 (3 files, 200MB)
            Would remove: /Users/ali/Library/Caches/Homebrew/firefox--119.0.dmg (120.5MB)
            """),
            "autoremove": BrewProbeResult(exitCode: 0, output: """
            ==> Would autoremove 2 unneeded formulae:
            libyaml
            pcre2
            """)
        ]
        probe.directorySizes = [
            "Homebrew": 1_000,
            "icons": 2_000,
            "libyaml": 300,
            "pcre2": 700
        ]
        probe.cachedInstallersResult = [
            CachedInstaller(name: "foo--1.0.zip", bytes: 900)
        ]
        let model = makeMaintenanceModel(probe: probe)
        XCTAssertFalse(model.hasDiskSnapshot)

        await model.refreshDisk()

        XCTAssertTrue(model.hasDiskSnapshot)
        XCTAssertEqual(model.cachedInstallers.map(\.name), ["foo--1.0.zip"])
        XCTAssertEqual(model.diskBytes[.cache], 1_000)
        XCTAssertEqual(model.diskBytes[.imageCache], 2_000)
        XCTAssertEqual(model.diskBytes[.oldVersions], 209_715_200)
        XCTAssertEqual(model.diskBytes[.orphans], 1_000)
        XCTAssertEqual(model.diskBytes[.apps], 0)
        XCTAssertEqual(model.orphanFormulae, ["libyaml", "pcre2"])
        XCTAssertEqual(model.reclaimableBytes, 209_715_200 + 1_000 + 1_000 + 2_000)
        XCTAssertEqual(
            model.orderedDiskCategories,
            [.oldVersions, .imageCache, .cache, .orphans, .apps]
        )
    }

    // MARK: - Cleaning

    @MainActor
    func test_clean_orphans_runs_autoremove_and_zeroes_row() async {
        let probe = RecordingMaintenanceProbe()
        let model = makeMaintenanceModel(probe: probe)

        await model.clean(.orphans)

        XCTAssertTrue(probe.commands.contains(["brew", "autoremove"]))
        XCTAssertEqual(model.rowStates[.orphans], .done)
        XCTAssertEqual(model.diskBytes[.orphans], 0)
        XCTAssertTrue(model.orphanFormulae.isEmpty)
    }

    @MainActor
    func test_clean_cache_removes_directory_contents() async {
        let probe = RecordingMaintenanceProbe()
        probe.cachedInstallersResult = [
            CachedInstaller(name: "foo--1.0.zip", bytes: 900)
        ]
        let model = makeMaintenanceModel(probe: probe)
        await model.refreshDisk()

        await model.clean(.cache)

        XCTAssertEqual(
            probe.removedDirectories.map(\.lastPathComponent),
            ["Homebrew"]
        )
        XCTAssertEqual(model.rowStates[.cache], .done)
        XCTAssertTrue(model.cachedInstallers.isEmpty)
    }

    @MainActor
    func test_clean_image_cache_calls_injected_closure() async {
        var cleared = false
        let model = makeMaintenanceModel(clearImageCache: { cleared = true })

        await model.clean(.imageCache)

        XCTAssertTrue(cleared)
        XCTAssertEqual(model.rowStates[.imageCache], .done)
        XCTAssertEqual(model.diskBytes[.imageCache], 0)
    }

    @MainActor
    func test_clean_failure_marks_row_and_returns_to_idle() async {
        let probe = RecordingMaintenanceProbe()
        probe.resultsByFirstArgument = [
            "autoremove": BrewProbeResult(exitCode: 1, output: "Error: nope")
        ]
        let model = makeMaintenanceModel(probe: probe)

        await model.clean(.orphans)

        XCTAssertEqual(model.rowStates[.orphans], .idle)
        XCTAssertTrue(model.failedRows.contains(.orphans))
    }

    @MainActor
    func test_apps_row_is_not_cleanable() async {
        let probe = RecordingMaintenanceProbe()
        let model = makeMaintenanceModel(probe: probe)

        await model.clean(.apps)

        XCTAssertTrue(probe.commands.isEmpty)
        XCTAssertNil(model.rowStates[.apps])
    }

    // MARK: - Homebrew Update

    @MainActor
    func test_updateHomebrew_runs_two_update_passes() async {
        let executor = RecordingHomebrewCommandExecutor()
        let homebrew = makeMaintenanceHomebrew(
            defaults: makeScratchDefaults("update-homebrew"),
            executor: executor
        )
        let model = makeMaintenanceModel(homebrew: homebrew)

        await model.updateHomebrew()

        XCTAssertEqual(executor.requests.map(\.arguments), [["update"], ["update"]])
        XCTAssertEqual(model.homebrewState, .done)
        XCTAssertFalse(model.homebrewFailed)
    }

    @MainActor
    func test_updateHomebrew_failure_sets_failed_flag() async {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [
            BrewProcessResult(exitCode: 1, output: "Error: update failed")
        ]
        let homebrew = LocalHomebrewService(
            defaults: makeScratchDefaults("update-homebrew-fail")
        ) {
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
            $0.processRunner = runner
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/opt/homebrew/bin/brew") }
            $0.brewVersionProvider = { "4.6.15" }
        }
        let model = makeMaintenanceModel(homebrew: homebrew)

        await model.updateHomebrew()

        XCTAssertTrue(model.homebrewFailed)
        XCTAssertEqual(model.homebrewState, .idle)
    }

    // MARK: - Freshness

    @MainActor
    func test_freshness_marks_both_widgets_current() async {
        let homebrew = makeMaintenanceHomebrew(defaults: makeScratchDefaults("freshness-current"))
        await homebrew.refresh()
        let model = makeMaintenanceModel(
            homebrew: homebrew,
            latestReleaseTag: { _, repo in repo == "brew" ? "4.6.15" : "v0.7.1" },
            categories: seededCategories([:], categories: [:], releaseTag: "v0.7.1")
        )

        await model.refreshFreshness()

        XCTAssertEqual(model.brewFreshness, .current)
        XCTAssertEqual(model.collectionFreshness, .current)
    }

    @MainActor
    func test_freshness_reports_updates_available() async {
        let homebrew = makeMaintenanceHomebrew(defaults: makeScratchDefaults("freshness-behind"))
        await homebrew.refresh()
        let model = makeMaintenanceModel(
            homebrew: homebrew,
            latestReleaseTag: { _, repo in repo == "brew" ? "9.9.9" : "v0.8.0" },
            categories: seededCategories([:], categories: [:], releaseTag: "v0.7.1")
        )

        await model.refreshFreshness()

        XCTAssertEqual(model.brewFreshness, .updateAvailable("9.9.9"))
        XCTAssertEqual(model.collectionFreshness, .updateAvailable("0.8.0"))
    }

    @MainActor
    func test_freshness_is_unknown_when_the_check_fails() async {
        let model = makeMaintenanceModel(latestReleaseTag: { _, _ in nil })

        await model.refreshFreshness()

        XCTAssertEqual(model.brewFreshness, .unknown)
        XCTAssertEqual(model.collectionFreshness, .unknown)
    }

    @MainActor
    func test_freshness_check_is_cached_within_the_ttl() async {
        let counter = Counter()
        let homebrew = makeMaintenanceHomebrew(defaults: makeScratchDefaults("freshness-ttl"))
        await homebrew.refresh()
        let model = makeMaintenanceModel(
            homebrew: homebrew,
            latestReleaseTag: { _, _ in
                counter.value += 1
                return "4.6.15"
            }
        )

        await model.refreshFreshness()
        await model.refreshFreshness()

        XCTAssertEqual(counter.value, 2)
        XCTAssertEqual(model.brewFreshness, .current)
    }

    @MainActor
    private final class Counter {
        var value = 0
    }

    // MARK: - Directories

    @MainActor
    func test_directories_point_at_the_expected_caches() {
        let model = makeMaintenanceModel()
        XCTAssertEqual(
            model.directories(for: .cache).map(\.lastPathComponent),
            ["Homebrew"]
        )
        XCTAssertEqual(
            model.directories(for: .imageCache).map(\.lastPathComponent),
            ["icons"]
        )
        XCTAssertFalse(model.directories(for: .apps).isEmpty)
    }
}
