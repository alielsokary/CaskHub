//
//  ConcurrentDownloadTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 05/10/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class ConcurrentDownloadTests: XCTestCase {
    func test_operation_waiting_for_its_turn_reads_queued_and_starts_when_the_lane_frees() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor)

        let first = Task { try? await service.uninstall(token: "firefox") }
        await executor.waitForRequests(1)
        let second = Task { try? await service.uninstall(token: "gimp") }
        await settle { service.operationStore.state(for: "gimp")?.progress?.phase == .queued }

        XCTAssertEqual(service.operationStore.state(for: "gimp")?.progress?.phase, .queued)
        XCTAssertEqual(service.operationStore.state(for: "gimp")?.canCancel, false)
        service.cancelInstall(token: "gimp")
        XCTAssertEqual(service.operationStore.state(for: "gimp")?.progress?.phase, .queued)
        XCTAssertEqual(executor.requests.map(\.arguments), [["uninstall", "--cask", "firefox"]])

        executor.finish("firefox")
        await executor.waitForRequests(2)
        XCTAssertEqual(service.operationStore.state(for: "gimp")?.progress?.phase, .performing)
        XCTAssertEqual(executor.maxActive["uninstall"], 1)
        executor.finish("gimp")
        await first.value
        await second.value
        XCTAssertNil(service.operationStore.state(for: "gimp"))
        XCTAssertEqual(executor.cancelledTokens, [])
    }

    func test_downloads_overlap_while_installs_run_one_at_a_time() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor)
        let tasks = ["a", "b", "c"].map { token in Task { try? await service.install(token: token) } }
        await executor.waitForRequests(3)
        XCTAssertEqual(executor.running("fetch"), ["a", "b", "c"])

        executor.finish("a")
        await settle { executor.running("install") == ["a"] }
        executor.finish("b")
        await settle { service.operationStore.state(for: "b")?.progress?.phase == .queued }
        XCTAssertEqual(executor.running("install"), ["a"])
        XCTAssertEqual(service.operationStore.state(for: "b")?.progress?.phase, .queued)
        XCTAssertEqual(service.operationStore.state(for: "b")?.canCancel, true)
        XCTAssertEqual(executor.running("fetch"), ["c"])

        await finishEverything(executor, tasks)
        XCTAssertEqual(executor.maxActive["fetch"], 3)
        XCTAssertEqual(executor.maxActive["install"], 1)
        XCTAssertEqual(executor.requests.filter { $0.arguments.first == "install" }.map(\.token), ["a", "b", "c"])
        for token in ["a", "b", "c"] { XCTAssertNil(service.operationStore.state(for: token)) }
    }

    func test_fourth_download_waits_for_a_slot() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor)
        let tokens = (0 ..< 4).map { "cask\($0)" }
        let tasks = tokens.map { token in Task { try? await service.install(token: token) } }
        await executor.waitForRequests(3)
        await settle { service.operationStore.state(for: "cask3")?.progress?.phase == .queued }

        XCTAssertEqual(executor.running("fetch").count, 3)
        XCTAssertEqual(service.operationStore.state(for: "cask3")?.progress?.phase, .queued)
        XCTAssertEqual(service.operationStore.state(for: "cask3")?.canCancel, true)

        executor.finish("cask0")
        await settle { executor.running("fetch").contains("cask3") }
        XCTAssertTrue(executor.running("fetch").contains("cask3"))

        await finishEverything(executor, tasks)
        XCTAssertEqual(executor.maxActive["fetch"], 3)
        XCTAssertEqual(executor.maxActive["install"], 1)
    }

    func test_update_cancelled_while_downloading_ends_clean_and_never_upgrades() async {
        for exitCode: Int32 in [130, 0] {
            let executor = ControlledHomebrewCommandExecutor()
            let service = makeService(executor)
            let update = Task { try? await service.upgrade(token: "firefox") }
            await executor.waitForRequests(1)
            XCTAssertEqual(service.operationStore.state(for: "firefox")?.canCancel, true)

            service.cancelInstall(token: "firefox")
            XCTAssertEqual(executor.cancelledTokens, ["firefox"])
            XCTAssertEqual(service.operationStore.state(for: "firefox")?.cancellationRequested, true)
            executor.finish("firefox", exitCode: exitCode)
            await update.value

            XCTAssertNil(service.operationStore.state(for: "firefox"), "exit \(exitCode)")
            XCTAssertEqual(executor.requests.map(\.arguments), [["fetch", "--cask", "firefox"]], "exit \(exitCode)")
        }
    }

    func test_fetch_stuck_connecting_gives_up_as_a_network_failure() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor, fetchStallTimeout: .milliseconds(50))
        let install = Task { try? await service.install(token: "mole-app") }
        await executor.waitForRequests(1)
        service.mutationCoordinator.consumeBrewOutput("==> Fetching mole-app from homebrew/cask\n", token: "mole-app")
        await service.mutationCoordinator.awaitPendingOutput()

        await settle { executor.cancelledTokens == ["mole-app"] }
        XCTAssertEqual(executor.cancelledTokens, ["mole-app"])
        executor.finish("mole-app", exitCode: 130)
        await install.value

        let unreachable = HomebrewCommandFailure(arguments: [], exitCode: 130, diagnostic: "", kind: .networkFailure)
        XCTAssertEqual(
            service.operationStore.state(for: "mole-app")?.failure?.message,
            LocalHomebrewError.brewCommandFailed(unreachable).errorDescription
        )
        XCTAssertEqual(executor.requests.map(\.arguments), [["fetch", "--cask", "mole-app"]])
    }

    func test_fetch_that_starts_downloading_in_time_is_left_alone() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor, fetchStallTimeout: .milliseconds(50))
        let install = Task { try? await service.install(token: "mole-app") }
        await executor.waitForRequests(1)
        service.mutationCoordinator.consumeBrewOutput(
            "==> Fetching mole-app from homebrew/cask\nCask mole-app    ##    Downloading    1.0MB/26.5MB\n",
            token: "mole-app"
        )
        await service.mutationCoordinator.awaitPendingOutput()

        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(executor.cancelledTokens, [])
        await finishEverything(executor, [install])
        XCTAssertNil(service.operationStore.state(for: "mole-app"))
    }

    func test_fetch_blocked_by_a_parallel_portable_ruby_upgrade_waits_and_retries() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor, brewLockRetryInterval: .milliseconds(20))
        let install = Task { try? await service.install(token: "zoom") }
        await executor.waitForRequests(1)

        executor.finish("zoom", exitCode: 1, output: Self.portableRubyLock)
        await executor.waitForRequests(2)
        XCTAssertNil(service.operationStore.state(for: "zoom")?.failure)
        XCTAssertEqual(executor.running("fetch"), ["zoom"])

        await finishEverything(executor, [install])
        XCTAssertNil(service.operationStore.state(for: "zoom"))
        XCTAssertEqual(executor.requests.map { $0.arguments.first }, ["fetch", "fetch", "install"])
    }

    func test_brew_lock_that_never_frees_gives_up_as_busy() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(
            executor,
            brewLockRetryInterval: .milliseconds(10),
            brewLockWaitLimit: .milliseconds(60)
        )
        let install = Task { try? await service.install(token: "zoom") }
        let deadline = Date().addingTimeInterval(5)
        while service.operationStore.state(for: "zoom")?.failure == nil, Date() < deadline {
            if executor.running("fetch") == ["zoom"] {
                executor.finish("zoom", exitCode: 1, output: Self.portableRubyLock)
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        await install.value

        let busy = HomebrewCommandFailure(arguments: [], exitCode: 1, diagnostic: "", kind: .brewBusy)
        XCTAssertEqual(
            service.operationStore.state(for: "zoom")?.failure?.message,
            LocalHomebrewError.brewCommandFailed(busy).errorDescription
        )
        XCTAssertGreaterThan(executor.requests.count, 1)
        XCTAssertFalse(executor.requests.contains { $0.arguments.first == "install" })
    }

    func test_cancel_while_waiting_for_a_brew_lock_ends_clean() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor, brewLockRetryInterval: .seconds(30))
        let install = Task { try? await service.install(token: "zoom") }
        await executor.waitForRequests(1)
        executor.finish("zoom", exitCode: 1, output: Self.portableRubyLock)

        await settle {
            service.cancelInstall(token: "zoom")
            return service.operationStore.state(for: "zoom") == nil
        }
        await install.value
        XCTAssertNil(service.operationStore.state(for: "zoom"))
        XCTAssertEqual(executor.requests.count, 1)
        XCTAssertEqual(executor.cancelledTokens, [])
    }

    private static let portableRubyLock = """
        lockf: 200: already locked
        Error: Another `brew vendor-install ruby` process is already running.
        Please wait for it to finish or terminate it to continue.
        Error: Failed to upgrade Homebrew Portable Ruby!
        """

    func test_cancel_while_queued_needs_no_process_and_frees_the_turn() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor)
        let blocker = Task { try? await service.uninstall(token: "blocker") }
        await executor.waitForRequests(1)
        let update = Task { try? await service.upgrade(token: "firefox") }
        await executor.waitForRequests(2)
        executor.finish("firefox")
        await settle { service.operationStore.state(for: "firefox")?.progress?.phase == .queued }
        XCTAssertEqual(service.operationStore.state(for: "firefox")?.canCancel, true)

        service.cancelInstall(token: "firefox")
        await update.value
        XCTAssertNil(service.operationStore.state(for: "firefox"))
        XCTAssertEqual(executor.cancelledTokens, [])

        let install = Task { try? await service.install(token: "gimp") }
        await executor.waitForRequests(3)
        executor.finish("gimp")
        await settle { service.operationStore.state(for: "gimp")?.progress?.phase == .queued }
        executor.finish("blocker")
        await blocker.value
        await executor.waitForRequests(4)
        XCTAssertEqual(executor.running("install"), ["gimp"])
        executor.finish("gimp")
        await install.value
        XCTAssertFalse(executor.requests.contains { $0.arguments.first == "upgrade" })
    }

    func test_running_upgrade_and_staged_replacement_cannot_be_cancelled() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor)
        let update = Task { try? await service.upgrade(token: "firefox") }
        await executor.waitForRequests(1)
        executor.finish("firefox")
        await executor.waitForRequests(2)
        XCTAssertEqual(executor.running("upgrade"), ["firefox"])
        XCTAssertEqual(service.operationStore.state(for: "firefox")?.canCancel, false)
        service.cancelInstall(token: "firefox")
        executor.finish("firefox")
        await update.value

        let repair = Task { try? await service.repairReinstalling(token: "zed") }
        for step in ["fetch", "uninstall", "install"] {
            await settle { executor.running(step) == ["zed"] }
            XCTAssertEqual(executor.running(step), ["zed"])
            XCTAssertEqual(service.operationStore.state(for: "zed")?.canCancel, false, step)
            service.cancelInstall(token: "zed")
            executor.finish("zed")
        }
        await repair.value
        XCTAssertEqual(executor.cancelledTokens, [])
    }

    func test_failed_download_stops_before_install_and_leaves_other_apps_alone() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor)
        let failing = Task { try? await service.install(token: "a") }
        let healthy = Task { try? await service.install(token: "b") }
        await executor.waitForRequests(2)

        executor.finish("a", exitCode: 1)
        await failing.value
        guard case .failed = service.operationStore.state(for: "a") else { return XCTFail("a should have failed") }
        XCTAssertEqual(service.operationStore.state(for: "b")?.action, .installing)

        await finishEverything(executor, [healthy])
        XCTAssertNil(service.operationStore.state(for: "b"))
        XCTAssertEqual(executor.requests.filter { $0.arguments.first == "install" }.map(\.token), ["b"])
    }

    func test_update_all_downloads_together_and_upgrades_one_at_a_time() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor)
        let batch = Task { await service.updateAll(tokens: ["a", "b", "c"]) }
        await executor.waitForRequests(3)

        XCTAssertEqual(Set(executor.running("fetch")), ["a", "b", "c"])
        XCTAssertTrue(service.isUpdatingAll)
        XCTAssertEqual(service.statusBarOperation?.message, String(localized: "Downloading \(3) of \(3)"))

        let deadline = Date().addingTimeInterval(10)
        while service.isUpdatingAll, Date() < deadline {
            if !executor.finishAny() { try? await Task.sleep(nanoseconds: 1_000_000) }
        }
        await batch.value
        XCTAssertFalse(service.isUpdatingAll)
        XCTAssertEqual(executor.maxActive["fetch"], 3)
        XCTAssertEqual(executor.maxActive["upgrade"], 1)
        XCTAssertEqual(Set(executor.requests.filter { $0.arguments.first == "upgrade" }.map(\.token)), ["a", "b", "c"])
        XCTAssertNil(service.statusBarOperation)
        XCTAssertNil(service.operationStore.batch)
    }

    func test_update_all_status_counts_downloads_out_of_what_is_left_and_shrinks_on_cancel() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor)
        let tokens = (0 ..< 6).map { "cask\($0)" }
        let batch = Task { await service.updateAll(tokens: tokens) }
        await executor.waitForRequests(3)
        await settle { service.operationStore.state(for: "cask5")?.progress?.phase == .queued }
        XCTAssertEqual(service.statusBarOperation?.message, String(localized: "Downloading \(3) of \(6)"))

        service.cancelInstall(token: "cask5")
        service.cancelInstall(token: "cask4")
        await settle { service.operationStore.batch?.finishedCount == 2 }
        XCTAssertEqual(service.operationStore.batch?.finishedCount, 2)
        XCTAssertEqual(service.statusBarOperation?.message, String(localized: "Downloading \(3) of \(4)"))

        let deadline = Date().addingTimeInterval(10)
        while service.isUpdatingAll, Date() < deadline {
            if !executor.finishAny() { try? await Task.sleep(nanoseconds: 1_000_000) }
        }
        await batch.value
        XCTAssertNil(service.statusBarOperation)
    }

    func test_install_all_downloads_together_and_counts_failures() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor)
        var finishedCounts: [Int] = []
        let batch = Task { await service.installAll(tokens: ["a", "b", "c"]) { finishedCounts.append($0) } }
        await executor.waitForRequests(3)
        XCTAssertEqual(Set(executor.running("fetch")), ["a", "b", "c"])

        executor.finish("b", exitCode: 1)
        await settle { finishedCounts == [1] }
        XCTAssertEqual(finishedCounts, [1])
        XCTAssertEqual(service.statusBarOperation?.message, String(localized: "Downloading \(2) of \(2)"))
        let deadline = Date().addingTimeInterval(10)
        while finishedCounts.count < 3, Date() < deadline {
            if !executor.finishAny() { try? await Task.sleep(nanoseconds: 1_000_000) }
        }
        let failedCount = await batch.value
        XCTAssertEqual(failedCount, 1)
        XCTAssertEqual(finishedCounts, [1, 2, 3])
        XCTAssertEqual(executor.maxActive["fetch"], 3)
        XCTAssertEqual(executor.maxActive["install"], 1)
        XCTAssertEqual(Set(executor.requests.filter { $0.arguments.first == "install" }.map(\.token)), ["a", "c"])
        XCTAssertNil(service.operationStore.batch)
    }

    func test_maintenance_probe_does_not_wait_for_a_running_download() async {
        let executor = ControlledHomebrewCommandExecutor()
        let service = makeService(executor, sharingLanesWithMaintenance: true)
        let install = Task { try? await service.install(token: "firefox") }
        await executor.waitForRequests(1)

        let result = await SystemMaintenanceProbe().run(URL(fileURLWithPath: "/usr/bin/true"), arguments: [], environment: nil)

        XCTAssertEqual(result?.exitCode, 0)
        XCTAssertEqual(executor.running("fetch"), ["firefox"])
        await finishEverything(executor, [install])
    }

    private func finishEverything(_ executor: ControlledHomebrewCommandExecutor, _ tasks: [Task<Void?, Never>]) async {
        var remaining = tasks.count
        for task in tasks {
            Task {
                _ = await task.value
                remaining -= 1
            }
        }
        let deadline = Date().addingTimeInterval(10)
        while remaining > 0, Date() < deadline {
            if !executor.finishAny() { try? await Task.sleep(nanoseconds: 1_000_000) }
        }
        XCTAssertEqual(remaining, 0, "operations did not finish")
    }

    private func makeService(
        _ executor: ControlledHomebrewCommandExecutor,
        sharingLanesWithMaintenance: Bool = false,
        fetchStallTimeout: Duration = .seconds(50),
        brewLockRetryInterval: Duration = .seconds(3),
        brewLockWaitLimit: Duration = .seconds(600)
    ) -> LocalHomebrewService {
        LocalHomebrewService(defaults: makeScratchDefaults("concurrent-\(UUID().uuidString)")) {
            $0.fileManager = NoFilesFileManager()
            $0.fetchStallTimeout = fetchStallTimeout
            $0.brewLockRetryInterval = brewLockRetryInterval
            $0.brewLockWaitLimit = brewLockWaitLimit
            $0.commandExecutor = executor
            $0.laneLimiter = sharingLanesWithMaintenance ? nil : HomebrewLaneLimiter(downloadLimit: 3)
            $0.softwareScanner = EmptyInstalledSoftwareScanner()
            $0.askpassProvider = { URL(fileURLWithPath: "/private/tmp/caskhub-test-askpass-\($0)") }
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
        }
    }

    private func settle(until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

@MainActor
final class ControlledHomebrewCommandExecutor: HomebrewCommandExecuting {
    private struct Pending {
        let request: HomebrewCommandRequest
        let continuation: CheckedContinuation<BrewProcessResult, Never>
    }

    private(set) var requests: [HomebrewCommandRequest] = []
    private(set) var cancelledTokens: [String] = []
    private(set) var maxActive: [String: Int] = [:]
    private var pending: [Pending] = []

    func execute(
        _ request: HomebrewCommandRequest,
        onStart: @escaping @MainActor @Sendable () -> Void,
        onChunk _: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> BrewProcessResult {
        requests.append(request)
        onStart()
        return await withCheckedContinuation { continuation in
            pending.append(Pending(request: request, continuation: continuation))
            let subcommand = request.arguments.first ?? ""
            maxActive[subcommand] = max(maxActive[subcommand, default: 0], running(subcommand).count)
        }
    }

    func cancel(token: String) -> Bool {
        guard pending.contains(where: { $0.request.token == token }) else { return false }
        cancelledTokens.append(token)
        return true
    }

    func running(_ subcommand: String) -> [String] {
        pending.filter { $0.request.arguments.first == subcommand }.map(\.request.token)
    }

    func finish(_ token: String, exitCode: Int32 = 0, signalled: Bool = false, output: String = "") {
        guard let index = pending.firstIndex(where: { $0.request.token == token }) else {
            return XCTFail("no running command for \(token)")
        }
        pending.remove(at: index).continuation.resume(
            returning: BrewProcessResult(exitCode: exitCode, output: output, wasTerminatedBySignal: signalled)
        )
    }

    func finishAny() -> Bool {
        guard let token = pending.first?.request.token else { return false }
        finish(token)
        return true
    }

    func waitForRequests(_ count: Int) async {
        let deadline = Date().addingTimeInterval(5)
        while requests.count < count, Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
