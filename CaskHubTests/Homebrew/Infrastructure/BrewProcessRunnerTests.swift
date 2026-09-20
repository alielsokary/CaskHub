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
    func test_collector_preserves_unicode_paths_across_utf8_reads() async throws {
        let prefix = "Preparing upgrade\nError: curl: (28) Operation timed out for /Applications/R"
        for character in ["é", "€", "💾"] {
            let bytes = Array(character.utf8)
            for split in 1 ..< bytes.count {
                let output = try await collect(
                    first: Data(prefix.utf8) + Data(bytes.prefix(split)),
                    second: Data(bytes.dropFirst(split)) + Data("sumé.app\n".utf8)
                )
                XCTAssertEqual(output, prefix + character + "sumé.app\n")
                XCTAssertEqual(HomebrewCommandFailure.classify(
                    arguments: ["upgrade", "--cask", "example"], exitCode: 1,
                    diagnostic: HomebrewOutputDiagnostics.make(from: output)
                ), .networkFailure)
            }
        }
    }

    @MainActor
    func test_collector_keeps_diagnostics_with_invalid_or_incomplete_utf8() async throws {
        let prefix = Data("Preparing upgrade\n".utf8)
        let diagnostic = "Error: curl: (28) Operation timed out\n"
        for (bytes, expected) in [
            (Data([0xFF]) + Data(diagnostic.utf8), "�" + diagnostic),
            (Data(diagnostic.utf8) + Data([0xE2, 0x82]), diagnostic + "�")
        ] {
            let output = try await collect(first: prefix, second: bytes)
            XCTAssertEqual(output, "Preparing upgrade\n" + expected)
            XCTAssertEqual(HomebrewCommandFailure.classify(
                arguments: ["upgrade"], exitCode: 1, diagnostic: output
            ), .networkFailure)
        }
    }

    @MainActor
    func test_collector_does_not_refilter_truncated_error_at_eof() async throws {
        let diagnostic = "Error: " + String(repeating: "x", count: 2100) + " tap trust is required\n"
        let output = try await collect(first: Data("Preparing upgrade\n".utf8), second: Data(diagnostic.utf8))
        XCTAssertEqual(output, String(diagnostic.suffix(2000)))
    }

    @MainActor
    private func collect(first: Data, second: Data) async throws -> String {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        process.standardInput = input.fileHandleForReading
        process.standardOutput = output.fileHandleForWriting
        let firstRead = expectation(description: "First output read consumed before sending the remainder")
        let (chunks, continuation) = AsyncStream<String>.makeStream()
        let delivery = Task {
            var text = ""
            for await chunk in chunks { text += chunk }
            return text
        }
        let collector = BrewOutputCollector()
        collector.attach(to: process, readHandle: output.fileHandleForReading) { text in
            continuation.yield(text)
            if text.contains("Preparing upgrade") { firstRead.fulfill() }
        }
        try process.run()
        try input.fileHandleForReading.close()
        try output.fileHandleForWriting.close()
        defer {
            if process.isRunning { process.terminate() }
            continuation.finish()
        }
        try input.fileHandleForWriting.write(contentsOf: first)
        await fulfillment(of: [firstRead], timeout: 2)
        try input.fileHandleForWriting.write(contentsOf: second)
        try input.fileHandleForWriting.close()
        let result = await collector.output()
        continuation.finish()
        let delivered = await delivery.value
        XCTAssertEqual(result, String(delivered.suffix(2000)))
        return result
    }

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
    func test_system_runner_preserves_handled_interrupt_exit_status() async throws {
        var process: Process?
        var interrupted = false
        let result = try await SystemBrewProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap 'exit 130' INT; printf 'ready\\n'; sleep 5; exit 124"],
            environment: ProcessInfo.processInfo.environment,
            onStart: { process = $0 },
            onChunk: { chunk in
                guard !interrupted, chunk.contains("ready") else { return }
                interrupted = true
                process?.interrupt()
            }
        )

        XCTAssertTrue(interrupted)
        XCTAssertEqual(result.exitCode, 130)
        XCTAssertFalse(result.wasTerminatedBySignal)
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
