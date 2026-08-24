//
//  BrewProcessRunnerTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 24/07/2026.
//

@testable import CaskHub
import XCTest

final class BrewProcessRunnerTests: XCTestCase {
    @MainActor
    func test_system_runner_collects_pseudo_terminal_output() async throws {
        let result = try await SystemBrewProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["terminal progress"],
            environment: ProcessInfo.processInfo.environment,
            onStart: { _ in },
            onChunk: { _ in }
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.wasTerminatedBySignal)
        XCTAssertTrue(result.output.contains("terminal progress"))
    }

    @MainActor
    func test_system_runner_reports_signal_termination() async throws {
        var process: Process?
        let resultTask = Task { @MainActor in
            try await SystemBrewProcessRunner().run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"],
                environment: ProcessInfo.processInfo.environment,
                onStart: { process = $0 },
                onChunk: { _ in }
            )
        }
        while process == nil { await Task.yield() }
        process?.terminate()

        let result = try await resultTask.value

        XCTAssertTrue(result.wasTerminatedBySignal)
    }

    @MainActor
    func test_system_runner_promotes_dumb_terminal_for_progress_output() async throws {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"

        let result = try await SystemBrewProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '%s' \"$TERM\""],
            environment: environment,
            onStart: { _ in },
            onChunk: { _ in }
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output, "xterm-256color")
    }

    @MainActor
    func test_system_runner_delivers_chunks_in_output_order() async throws {
        var deliveredOutput = ""
        let result = try await SystemBrewProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf first; sleep 0.05; printf second; sleep 0.05; printf third"],
            environment: ProcessInfo.processInfo.environment,
            onStart: { _ in },
            onChunk: { deliveredOutput += $0 }
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(deliveredOutput, "firstsecondthird")
        XCTAssertEqual(result.output, deliveredOutput)
    }
}
