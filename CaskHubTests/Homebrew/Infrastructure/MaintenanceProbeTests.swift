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

    func test_removeDirectoryContents_fails_for_missing_directory() async {
        let succeeded = await probe.removeDirectoryContents(
            at: root.appendingPathComponent("missing")
        )
        XCTAssertFalse(succeeded)
    }
}
