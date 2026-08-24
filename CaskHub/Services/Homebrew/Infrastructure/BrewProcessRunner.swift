//
//  BrewProcessRunner.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Darwin
import Foundation

struct BrewProcessResult: Sendable {
    let exitCode: Int32
    let output: String
    let wasTerminatedBySignal: Bool

    init(
        exitCode: Int32,
        output: String,
        wasTerminatedBySignal: Bool = false
    ) {
        self.exitCode = exitCode
        self.output = output
        self.wasTerminatedBySignal = wasTerminatedBySignal
    }
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
        onChunk: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> BrewProcessResult
}

@MainActor
final class SystemBrewProcessRunner: BrewProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        onStart: @escaping (Process) -> Void,
        onChunk: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> BrewProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let terminal = BrewPseudoTerminal()
        let readHandle: FileHandle
        if let terminal {
            var terminalEnvironment = environment
            terminalEnvironment["TERM"] = "xterm-256color"
            // stty can't size the pty (stdin nulled); tput honors COLUMNS, else 80-col clipping.
            terminalEnvironment["COLUMNS"] = "180"
            process.environment = terminalEnvironment
            process.standardOutput = terminal.childHandle
            process.standardError = terminal.childHandle
            readHandle = terminal.outputHandle
        } else {
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            readHandle = pipe.fileHandleForReading
        }

        let (chunkStream, chunkContinuation) = AsyncStream<String>.makeStream()
        let deliveryTask = Task { @MainActor in
            for await chunk in chunkStream {
                onChunk(chunk)
            }
        }

        let collector = BrewOutputCollector()
        collector.attach(to: process, readHandle: readHandle) { chunk in
            chunkContinuation.yield(chunk)
        }

        do {
            try process.run()
        } catch {
            chunkContinuation.finish()
            await deliveryTask.value
            throw error
        }
        terminal?.childHandle.closeFile()
        onStart(process)

        let output = await collector.output()
        chunkContinuation.finish()
        await deliveryTask.value
        return BrewProcessResult(
            exitCode: process.terminationStatus,
            output: output,
            wasTerminatedBySignal: process.terminationReason == .uncaughtSignal
        )
    }
}

private struct BrewPseudoTerminal {
    let outputHandle: FileHandle
    let childHandle: FileHandle

    init?() {
        var outputDescriptor: Int32 = -1
        var childDescriptor: Int32 = -1
        var size = winsize()
        size.ws_row = 24
        size.ws_col = 180

        guard openpty(
            &outputDescriptor,
            &childDescriptor,
            nil,
            nil,
            &size
        ) == 0 else {
            return nil
        }
        outputHandle = FileHandle(fileDescriptor: outputDescriptor, closeOnDealloc: true)
        childHandle = FileHandle(fileDescriptor: childDescriptor, closeOnDealloc: true)
    }
}
