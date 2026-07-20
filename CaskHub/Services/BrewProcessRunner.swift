//
//  BrewProcessRunner.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Foundation

struct BrewProcessResult: Sendable {
    let exitCode: Int32
    let output: String
}

/// Execution seam for Homebrew mutations. Tests can supply deterministic
/// command results without invoking the user's real brew installation.
@MainActor
protocol BrewProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        onStart: @escaping (Process) -> Void,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> BrewProcessResult
}

@MainActor
final class SystemBrewProcessRunner: BrewProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        onStart: @escaping (Process) -> Void,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> BrewProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let collector = BrewOutputCollector()
        collector.attach(to: process, pipe: pipe, onChunk: onChunk)

        try process.run()
        onStart(process)

        let output = await collector.output()
        return BrewProcessResult(
            exitCode: process.terminationStatus,
            output: output
        )
    }
}
