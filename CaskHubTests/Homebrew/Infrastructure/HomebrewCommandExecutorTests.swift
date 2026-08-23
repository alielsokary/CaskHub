//
//  HomebrewCommandExecutorTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 25/07/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class HomebrewCommandExecutorTests: XCTestCase {
    func test_incompatible_brew_is_rejected_before_process_start() async {
        let executor = SuspendingHomebrewCommandExecutor()
        let incompatiblePrefix = HomebrewLocator.isAppleSilicon
            ? HomebrewLocator.intelPrefix
            : HomebrewLocator.appleSiliconPrefix
        let incompatibleBrewURL = URL(fileURLWithPath: incompatiblePrefix)
            .appendingPathComponent("bin/brew")
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("incompatible-brew")
        ) {
            $0.commandExecutor = executor
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
            $0.brewBinaryProvider = { incompatibleBrewURL }
            $0.brewVersionProvider = { "test" }
        }

        do {
            try await service.install(token: "gamehub")
            XCTFail("incompatible Homebrew must fail before starting a process")
        } catch LocalHomebrewError.incompatibleBrewPath {
            XCTAssertTrue(executor.requests.isEmpty)
            XCTAssertTrue(
                service.operationStore.state(for: "gamehub")?
                    .failure?.message.contains("Settings") == true
            )
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_service_cancellation_routes_through_executor_and_state_machine() async {
        let executor = SuspendingHomebrewCommandExecutor()
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("command-cancellation")
        ) {
            $0.commandExecutor = executor
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
            $0.brewBinaryProvider = {
                URL(fileURLWithPath: "/test/bin/brew")
            }
            $0.brewVersionProvider = { "test" }
        }

        let mutation = Task {
            try? await service.install(token: "firefox")
        }
        while executor.requests.isEmpty {
            await Task.yield()
        }

        XCTAssertTrue(service.operationStore.state(for: "firefox")?.canCancel == true)
        service.cancelInstall(token: "firefox")
        XCTAssertEqual(executor.cancelledTokens, ["firefox"])
        XCTAssertTrue(
            service.operationStore.state(for: "firefox")?.cancellationRequested == true
        )

        executor.finish(BrewProcessResult(
            exitCode: 2,
            output: "interrupted",
            wasTerminatedBySignal: true
        ))
        await mutation.value

        XCTAssertNil(service.operationStore.state(for: "firefox"))
    }

    func test_failure_after_cancel_request_is_not_mistaken_for_process_cancellation() async {
        let executor = SuspendingHomebrewCommandExecutor()
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("cancel-race-failure")
        ) {
            $0.commandExecutor = executor
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
        }
        let mutation = Task { try? await service.install(token: "firefox") }
        while executor.requests.isEmpty { await Task.yield() }

        service.cancelInstall(token: "firefox")
        executor.finish(BrewProcessResult(
            exitCode: 1,
            output: "Error: rollback failed"
        ))
        await mutation.value

        XCTAssertNotNil(service.operationStore.state(for: "firefox")?.failure)
    }

    func test_services_share_global_process_fifo() async throws {
        let overlap = expectation(description: "Homebrew processes overlap")
        overlap.isInverted = true
        let runner = ControlledBrewProcessRunner(overlapExpectation: overlap)
        func makeService(_ name: String) -> LocalHomebrewService {
            LocalHomebrewService(defaults: makeScratchDefaults(name)) {
                $0.fileManager = NoFilesFileManager()
                $0.commandExecutor = SystemHomebrewCommandExecutor(processRunner: runner)
                $0.softwareScanner = EmptyInstalledSoftwareScanner()
                $0.askpassProvider = { token in
                    URL(fileURLWithPath: "/private/tmp/caskhub-test-askpass-\(token)")
                }
                $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
                $0.brewVersionProvider = { "test" }
            }
        }
        let firstService = makeService("serialized-homebrew-first")
        let secondService = makeService("serialized-homebrew-second")

        let first = Task { try await firstService.install(token: "firefox") }
        await runner.waitForStarts(1)
        let second = Task { try await secondService.install(token: "gimp") }

        await fulfillment(of: [overlap], timeout: 0.1)
        runner.finishNext()
        await runner.waitForStarts(2)
        runner.finishNext()

        try await first.value
        try await second.value
        XCTAssertEqual(runner.maxActiveCount, 1)
        XCTAssertEqual(runner.requests, [
            ["install", "--cask", "firefox"],
            ["install", "--cask", "gimp"]
        ])
        XCTAssertNil(firstService.operationStore.state(for: "firefox"))
        XCTAssertNil(secondService.operationStore.state(for: "gimp"))
    }

    func test_maintenance_probe_waits_for_running_mutation() async throws {
        let processOverlap = expectation(description: "Homebrew processes overlap")
        processOverlap.isInverted = true
        let maintenanceFinished = expectation(description: "maintenance finished early")
        maintenanceFinished.isInverted = true
        let runner = ControlledBrewProcessRunner(overlapExpectation: processOverlap)
        let executor = SystemHomebrewCommandExecutor(processRunner: runner)
        let mutation = Task {
            try await executor.execute(
                HomebrewCommandRequest(
                    token: "firefox",
                    executableURL: URL(fileURLWithPath: "/test/bin/brew"),
                    arguments: ["install", "--cask", "firefox"],
                    environment: [:]
                ),
                onStart: {},
                onChunk: { _ in }
            )
        }
        await runner.waitForStarts(1)
        let maintenance = Task {
            let result = await SystemMaintenanceProbe().run(
                URL(fileURLWithPath: "/usr/bin/true"),
                arguments: [],
                environment: nil
            )
            maintenanceFinished.fulfill()
            return result
        }

        await fulfillment(of: [processOverlap, maintenanceFinished], timeout: 0.1)
        runner.finishNext()

        _ = try await mutation.value
        let maintenanceResult = await maintenance.value
        XCTAssertEqual(maintenanceResult?.exitCode, 0)
    }

    func test_homebrew_update_blocks_other_tokens_until_both_passes_finish() async {
        let executor = SuspendingHomebrewCommandExecutor()
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("global-homebrew-update")
        ) {
            $0.commandExecutor = executor
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
        }

        let update = Task { try? await service.updateHomebrew(for: "gimp") }
        while executor.requests.count < 1 { await Task.yield() }

        try? await service.install(token: "firefox")
        await service.updateAll(tokens: ["zed", "zoom"])
        XCTAssertEqual(executor.requests.map(\.arguments), [["update"]])
        XCTAssertNil(service.operationStore.state(for: "zed"))
        XCTAssertNil(service.operationStore.state(for: "zoom"))
        XCTAssertFalse(service.isUpdatingAll)

        executor.finish(BrewProcessResult(exitCode: 0, output: "first pass"))
        while executor.requests.count < 2 { await Task.yield() }

        try? await service.install(token: "firefox")
        XCTAssertEqual(executor.requests.map(\.arguments), [["update"], ["update"]])

        executor.finish(BrewProcessResult(exitCode: 0, output: "second pass"))
        await update.value

        let install = Task { try? await service.install(token: "firefox") }
        while executor.requests.count < 3 { await Task.yield() }
        XCTAssertEqual(executor.requests.last?.arguments, ["install", "--cask", "firefox"])
        XCTAssertEqual(service.brewVersion, "test")

        try? await service.updateHomebrew(for: "gimp")
        XCTAssertEqual(service.brewVersion, "test")
        XCTAssertEqual(executor.requests.count, 3)

        executor.finish(BrewProcessResult(exitCode: 0, output: "installed"))
        await install.value
    }
}

@MainActor
private final class ControlledBrewProcessRunner: BrewProcessRunning {
    private let overlapExpectation: XCTestExpectation
    private var activeCount = 0
    private var continuations: [CheckedContinuation<BrewProcessResult, Never>] = []
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    private(set) var maxActiveCount = 0
    private(set) var requests: [[String]] = []

    init(overlapExpectation: XCTestExpectation) {
        self.overlapExpectation = overlapExpectation
    }

    func run(
        executableURL _: URL,
        arguments: [String],
        environment _: [String: String],
        onStart: @escaping (Process) -> Void,
        onChunk _: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> BrewProcessResult {
        requests.append(arguments)
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
        if activeCount > 1 { overlapExpectation.fulfill() }
        resumeStartWaiters()
        onStart(Process())
        return await withCheckedContinuation { continuations.append($0) }
    }

    func waitForStarts(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func finishNext() {
        precondition(!continuations.isEmpty)
        activeCount -= 1
        continuations.removeFirst().resume(
            returning: BrewProcessResult(exitCode: 0, output: "")
        )
    }

    private func resumeStartWaiters() {
        let ready = startWaiters.filter { $0.0 <= requests.count }
        startWaiters.removeAll { $0.0 <= requests.count }
        ready.forEach { $0.1.resume() }
    }
}

@MainActor
private final class SuspendingHomebrewCommandExecutor: HomebrewCommandExecuting {
    private(set) var requests: [HomebrewCommandRequest] = []
    private(set) var cancelledTokens: [String] = []
    private var continuation: CheckedContinuation<BrewProcessResult, Never>?

    func execute(
        _ request: HomebrewCommandRequest,
        onStart: @escaping @MainActor @Sendable () -> Void,
        onChunk _: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> BrewProcessResult {
        requests.append(request)
        onStart()
        return await withCheckedContinuation { continuation = $0 }
    }

    func cancel(token: String) -> Bool {
        guard continuation != nil else { return false }
        cancelledTokens.append(token)
        return true
    }

    func finish(_ result: BrewProcessResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
