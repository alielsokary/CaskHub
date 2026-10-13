//
//  ScratchDefaultsTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 13/10/2026.
//

@testable import CaskHub
import XCTest

final class ScratchDefaultsTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fileManager.temporaryDirectory
            .appendingPathComponent("scratch-defaults-\(UUID().uuidString)")
        try fileManager.createDirectory(at: manifests, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: preferences, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    private var manifests: URL { root.appendingPathComponent("manifests") }
    private var preferences: URL { root.appendingPathComponent("Preferences") }

    private func exists(_ name: String, in directory: URL) -> Bool {
        fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
    }

    func test_sweep_deletes_only_suites_recorded_by_finished_processes() throws {
        try Data("test.finished-a\ntest.finished-b\n".utf8)
            .write(to: manifests.appendingPathComponent("111.txt"))
        try Data("test.still-running\n".utf8)
            .write(to: manifests.appendingPathComponent("222.txt"))
        for name in ["test.finished-a", "test.finished-b", "test.still-running", "test.someone-elses"] {
            try Data().write(to: preferences.appendingPathComponent("\(name).plist"))
        }

        ScratchDefaults.sweep(manifests: manifests, preferences: preferences) { $0 == 222 }

        XCTAssertFalse(exists("test.finished-a.plist", in: preferences))
        XCTAssertFalse(exists("test.finished-b.plist", in: preferences))
        XCTAssertFalse(exists("111.txt", in: manifests))
        XCTAssertTrue(exists("test.still-running.plist", in: preferences))
        XCTAssertTrue(exists("222.txt", in: manifests))
        XCTAssertTrue(exists("test.someone-elses.plist", in: preferences))
    }

    func test_every_scratch_suite_is_recorded_for_the_next_run_to_delete() throws {
        _ = makeScratchDefaults("scratch-defaults-recorded")

        let recorded = try String(contentsOf: ScratchDefaults.shared.manifest, encoding: .utf8)
        XCTAssertTrue(recorded.components(separatedBy: "\n").contains("test.scratch-defaults-recorded"))
    }
}
