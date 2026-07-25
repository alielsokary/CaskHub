//
//  HomebrewCommandExecutorTests.swift
//  CaskHubTests
//

@testable import CaskHub
import XCTest

@MainActor
final class HomebrewCommandExecutorTests: XCTestCase {
    func test_service_cancellation_routes_through_executor_and_state_machine() async {
        let executor = SuspendingHomebrewCommandExecutor()
        let service = LocalHomebrewService(
            defaults: makeScratchDefaults("command-cancellation"),
            commandExecutor: executor,
            softwareScanner: EmptyInstalledSoftwareScanner(),
            brewBinaryProvider: { URL(fileURLWithPath: "/test/bin/brew") },
            brewVersionProvider: { "test" }
        )

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

private nonisolated struct EmptyInstalledSoftwareScanner: InstalledSoftwareScanning {
    func scan(_ request: InstalledSoftwareScanRequest) async -> InstallationSnapshot {
        .empty
    }

    func reconcileCatalog(
        _ request: InstalledSoftwareScanRequest,
        with current: InstallationSnapshot
    ) async -> InstallationSnapshot {
        current
    }
}
