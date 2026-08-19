//
//  MaintenanceProbeTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 19/08/2026.
//

@testable import CaskHub
import XCTest

final class MaintenanceProbeTests: XCTestCase {
    private let probe = SystemMaintenanceProbe()
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("maintenance-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    func test_run_captures_both_streams_and_exit_code() async {
        let result = await probe.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo out; echo err 1>&2; exit 3"]
        )

        XCTAssertEqual(result?.exitCode, 3)
        XCTAssertTrue(result?.output.contains("out") == true)
        XCTAssertTrue(result?.output.contains("err") == true)
    }

    func test_run_merges_environment_overrides() async {
        let result = await probe.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo $PATH"],
            environment: ["PATH": "/probe-test-bin:/usr/bin"]
        )

        XCTAssertEqual(result?.exitCode, 0)
        XCTAssertTrue(result?.output.hasPrefix("/probe-test-bin:") == true)
    }

    func test_run_returns_nil_for_missing_executable() async {
        let result = await probe.run(
            root.appendingPathComponent("no-such-binary"),
            arguments: []
        )
        XCTAssertNil(result)
    }

    func test_directorySize_sums_nested_files() async throws {
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 10_000)
            .write(to: root.appendingPathComponent("a.bin"))
        try Data(repeating: 0, count: 20_000)
            .write(to: nested.appendingPathComponent("b.bin"))

        let size = await probe.directorySize(at: root)

        XCTAssertGreaterThanOrEqual(size, 30_000)
    }

    func test_directorySize_of_missing_directory_is_zero() async {
        let size = await probe.directorySize(at: root.appendingPathComponent("missing"))
        XCTAssertEqual(size, 0)
    }

    func test_removeDirectoryContents_empties_the_directory() async throws {
        try Data("x".utf8).write(to: root.appendingPathComponent("file.txt"))
        let nested = root.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("y".utf8).write(to: nested.appendingPathComponent("inner.txt"))

        let succeeded = await probe.removeDirectoryContents(at: root)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func test_cachedInstallers_resolves_symlinks_from_cask_dir_and_root() async throws {
        let caskDir = root.appendingPathComponent("Cask")
        let downloadsDir = root.appendingPathComponent("downloads")
        try FileManager.default.createDirectory(at: caskDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        let caskPayload = downloadsDir.appendingPathComponent("abc--Foo.zip")
        try Data(repeating: 0, count: 20_000).write(to: caskPayload)
        let bottlePayload = downloadsDir.appendingPathComponent("def--mole.bottle.tar.gz")
        try Data(repeating: 0, count: 5_000).write(to: bottlePayload)
        let manifestPayload = downloadsDir.appendingPathComponent("fe5--mole.bottle_manifest.json")
        try Data("{}".utf8).write(to: manifestPayload)
        try FileManager.default.createSymbolicLink(
            at: caskDir.appendingPathComponent("foo--1.0.zip"),
            withDestinationURL: caskPayload
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("mole--1.50.0"),
            withDestinationURL: bottlePayload
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("mole_bottle_manifest--1.50.0"),
            withDestinationURL: manifestPayload
        )
        try Data("x".utf8).write(to: root.appendingPathComponent("all_commands_list.txt"))

        let installers = await probe.cachedInstallers(at: root)

        XCTAssertEqual(installers.map(\.name), ["foo--1.0.zip", "mole--1.50.0"])
        XCTAssertGreaterThanOrEqual(installers[0].bytes, 20_000)
        XCTAssertGreaterThanOrEqual(installers[1].bytes, 5_000)
    }

    func test_cachedInstallers_resolves_cask_aliases_to_payload_sizes() async throws {
        let caskDir = root.appendingPathComponent("Cask")
        let downloadsDir = root.appendingPathComponent("downloads")
        try FileManager.default.createDirectory(at: caskDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        let payload = downloadsDir.appendingPathComponent("abc123--Foo.zip")
        try Data(repeating: 0, count: 10_000).write(to: payload)
        let bookmark = try payload.bookmarkData(
            options: .suitableForBookmarkFile,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try URL.writeBookmarkData(bookmark, to: caskDir.appendingPathComponent("foo--1.0.zip"))
        try Data("{}".utf8).write(to: caskDir.appendingPathComponent("descriptions.json"))

        let installers = await probe.cachedInstallers(at: root)

        XCTAssertEqual(installers.map(\.name), ["foo--1.0.zip"])
        XCTAssertGreaterThanOrEqual(installers[0].bytes, 10_000)
    }

    func test_cachedInstallers_is_empty_without_cask_directory() async {
        let installers = await probe.cachedInstallers(at: root)
        XCTAssertTrue(installers.isEmpty)
    }

    func test_removeDirectoryContents_fails_for_missing_directory() async {
        let succeeded = await probe.removeDirectoryContents(
            at: root.appendingPathComponent("missing")
        )
        XCTAssertFalse(succeeded)
    }
}
