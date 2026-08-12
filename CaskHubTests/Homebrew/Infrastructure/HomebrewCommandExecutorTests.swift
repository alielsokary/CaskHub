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

        executor.finish(BrewProcessResult(exitCode: 130, output: "interrupted"))
        await mutation.value

        XCTAssertNil(service.operationStore.state(for: "firefox"))
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
