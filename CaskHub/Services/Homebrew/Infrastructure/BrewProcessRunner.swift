//
//  BrewProcessRunner.swift
//  CaskHub
//
//  Created by Ali Elsokary on 20/07/2026.
//

import Darwin
import Foundation
import LocalAuthentication

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
    private let canUseTouchID: @MainActor () -> Bool

    init(
        canUseTouchID: @escaping @MainActor () -> Bool = {
            HomebrewAdministratorAuthentication.isAvailable()
        }
    ) {
        self.canUseTouchID = canUseTouchID
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        onStart: @escaping (Process) -> Void,
        onChunk: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> BrewProcessResult {
        let authorization = makeAuthorization(arguments: arguments, environment: environment)
        defer { authorization?.closeInput() }
        let process = makeProcess(executableURL: executableURL, arguments: arguments, authorization: authorization)
        let output = configureOutput(of: process, environment: authorization?.environment ?? environment)

        let (chunkStream, chunkContinuation) = AsyncStream<String>.makeStream()
        let deliveryTask = Task { @MainActor in
            for await chunk in chunkStream {
                onChunk(chunk)
            }
        }

        let collector = BrewOutputCollector()
        collector.attach(to: process, readHandle: output.readHandle) { chunk in
            chunkContinuation.yield(chunk)
        }

        do {
            try process.run()
        } catch {
            chunkContinuation.finish()
            await deliveryTask.value
            throw error
        }
        output.childHandle?.closeFile()
        let authorizationMonitor = authorization?.monitor(process: process)
        defer { authorizationMonitor?.cancel() }
        onStart(process)

        let collected = await collector.output()
        authorizationMonitor?.cancel()
        await authorizationMonitor?.value
        chunkContinuation.finish()
        await deliveryTask.value
        return BrewProcessResult(
            exitCode: authorization?.declined == true ? 130 : process.terminationStatus,
            output: collected,
            wasTerminatedBySignal: process.terminationReason == .uncaughtSignal
        )
    }

    private func makeAuthorization(arguments: [String], environment: [String: String]) -> NativeHomebrewAuthorization? {
        guard HomebrewAdministratorAuthentication.shouldUseTerminal(arguments: arguments, environment: environment),
              canUseTouchID(), let askpass = environment["SUDO_ASKPASS"]
        else { return nil }
        return NativeHomebrewAuthorization(environment: environment, askpass: URL(fileURLWithPath: askpass))
    }

    private func makeProcess(
        executableURL: URL, arguments: [String], authorization: NativeHomebrewAuthorization?
    ) -> Process {
        let process = Process()
        if let authorization {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            process.arguments = [
                "-q", "-e", "/dev/null", "/bin/sh", "-c", HomebrewAdministratorAuthentication.launcher,
                "caskhub-authenticate", authorization.terminalFile.path, executableURL.path
            ] + arguments
            process.standardInput = authorization.input.fileHandleForReading
        } else {
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
        }
        return process
    }

    private func configureOutput(
        of process: Process, environment: [String: String]
    ) -> (readHandle: FileHandle, childHandle: FileHandle?) {
        if let terminal = BrewPseudoTerminal() {
            var terminalEnvironment = environment
            terminalEnvironment["TERM"] = "xterm-256color"
            terminalEnvironment["COLUMNS"] = "180"
            process.environment = terminalEnvironment
            process.standardOutput = terminal.childHandle
            process.standardError = terminal.childHandle
            return (terminal.outputHandle, terminal.childHandle)
        }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        return (pipe.fileHandleForReading, nil)
    }
}

enum HomebrewAdministratorAuthentication {
    static func isAvailable() -> Bool {
        touchIDIsConfigured() && LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static func shouldUseTerminal(arguments: [String], environment: [String: String]) -> Bool {
        guard let command = arguments.first,
              ["install", "upgrade", "reinstall", "uninstall"].contains(command),
              !arguments.contains("--dry-run"),
              !arguments.contains("--help"),
              let askpass = environment["SUDO_ASKPASS"], !askpass.isEmpty,
              environment["HOMEBREW_NO_SUDO", default: ""].isEmpty,
              environment["HOMEBREW_SUDO_THROUGH_SUDO_USER", default: ""].isEmpty
        else { return false }
        return true
    }

    static func touchIDIsConfigured(
        readConfiguration: (String) -> String? = { try? String(contentsOfFile: "/etc/pam.d/" + $0, encoding: .utf8) }
    ) -> Bool {
        var visited = Set<String>()
        return includesTouchID(service: "sudo", read: readConfiguration, visited: &visited)
    }

    private static func includesTouchID(
        service: String, read: (String) -> String?, visited: inout Set<String>
    ) -> Bool {
        guard visited.insert(service).inserted, visited.count <= 32, let configuration = read(service) else {
            return false
        }
        for line in configuration.split(whereSeparator: \.isNewline) {
            let rule = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let fields = rule.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 3, fields[0] == "auth" else { continue }
            if fields[1] == "sufficient", fields[2].split(separator: "/").last == "pam_tid.so" { return true }
            if fields[1] == "include", includesTouchID(service: String(fields[2]), read: read, visited: &visited) {
                return true
            }
        }
        return false
    }

    // A controlling terminal lets sudo use macOS authorization instead of -A.
    // Brew's ordinary stdin stays closed; we never collect terminal passwords.
    static let launcher = """
    tty > "$1"
    shift
    stty echo rows 24 columns 180
    exec "$@" </dev/null
    """
}

private final class NativeHomebrewAuthorization {
    let input = Pipe()
    let terminalFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("caskhub-terminal-\(UUID().uuidString)")
    let cancellationMarker: URL
    var environment: [String: String]
    private(set) var declined = false

    init?(environment: [String: String], askpass: URL) {
        self.environment = environment
        self.environment["SUDO_ASKPASS"] = nil
        cancellationMarker = AskpassScriptManager.cancellationMarker(for: askpass)
        guard FileManager.default.createFile(
            atPath: terminalFile.path, contents: Data(), attributes: [.posixPermissions: 0o600]
        ) else { return nil }
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    func monitor(process: Process) -> Task<Void, Never> {
        Task { @MainActor in
            var terminal: Int32 = -1
            defer { if terminal >= 0 { Darwin.close(terminal) } }
            while !Task.isCancelled, process.isRunning {
                if terminal < 0 { terminal = openTerminal() }
                var attributes = termios()
                if terminal >= 0, tcgetattr(terminal, &attributes) == 0,
                   attributes.c_lflag & tcflag_t(ECHO) == 0 {
                    await decline(process: process)
                    return
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
    }

    private func openTerminal() -> Int32 {
        guard let name = try? String(contentsOf: terminalFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            name.hasPrefix("/dev/ttys"), !name.dropFirst(9).isEmpty,
            name.dropFirst(9).allSatisfy(\.isNumber)
        else { return -1 }
        return Darwin.open(name, O_RDONLY | O_NOCTTY | O_CLOEXEC)
    }

    func decline(process: Process) async {
        guard !declined else { return }
        declined = true
        try? Data().write(to: cancellationMarker, options: .atomic)
        // PAM falls through to terminal password input after the system dialog
        // is canceled. Interrupt brew before sending EOF so optional failures
        // cannot continue. Keep script alive for brew's cleanup and output.
        let pid = process.processIdentifier
        await Task.detached { SystemHomebrewCommandExecutor.interruptChildren(of: pid) }.value
        try? input.fileHandleForWriting.write(contentsOf: Data([4]))
        try? input.fileHandleForWriting.close()
    }

    func closeInput() {
        try? input.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        try? FileManager.default.removeItem(at: terminalFile)
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
