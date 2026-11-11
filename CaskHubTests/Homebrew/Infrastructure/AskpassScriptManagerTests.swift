//
//  AskpassScriptManagerTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 06/11/2026.
//

@testable import CaskHub
import XCTest

final class AskpassScriptManagerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("askpass-manager-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func test_script_passes_the_attempt_marker() async throws {
        let script = try await makeScript()
        let text = try String(contentsOf: script, encoding: .utf8)
        let marker = AskpassScriptManager.attemptMarker(for: script)
        XCTAssertEqual(marker.path, script.path + ".attempts")
        XCTAssertTrue(text.contains("--askpass-attempt-marker '\(marker.path)'"))
    }

    func test_remove_deletes_script_cancel_and_attempt_markers() async throws {
        let script = try await makeScript()
        let cancel = AskpassScriptManager.cancellationMarker(for: script)
        let attempts = AskpassScriptManager.attemptMarker(for: script)
        try Data().write(to: cancel)
        try Data("1".utf8).write(to: attempts)

        await AskpassScriptManager.remove(at: script)

        for url in [script, cancel, attempts] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent)
        }
    }

    private func makeScript() async throws -> URL {
        try await AskpassScriptManager.create(
            token: "zoom",
            directory: directory,
            executableURL: URL(fileURLWithPath: "/Applications/CaskHub.app/Contents/MacOS/CaskHub")
        )
    }
}
