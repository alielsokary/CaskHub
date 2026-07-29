//
//  ApplicationTerminationCoordinatorTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 29/07/2026.
//

@testable import CaskHub
import XCTest

final class ApplicationTerminationCoordinatorTests: XCTestCase {
    @MainActor
    private final class Probe {
        var hasActiveOperations = false
        var requestCount = 0
        var replies: [Bool] = []
    }

    @MainActor
    private func makeCoordinator(
        probe: Probe
    ) -> ApplicationTerminationCoordinator {
        ApplicationTerminationCoordinator(
            hasActiveOperations: { probe.hasActiveOperations },
            requestApplicationTermination: { probe.requestCount += 1 },
            replyToApplicationTermination: { probe.replies.append($0) }
        )
    }

    @MainActor
    func test_request_termination_uses_the_application_termination_path() {
        let probe = Probe()
        let coordinator = makeCoordinator(probe: probe)

        coordinator.requestTermination()

        XCTAssertEqual(probe.requestCount, 1)
    }

    @MainActor
    func test_termination_proceeds_immediately_without_active_operations() {
        let probe = Probe()
        let coordinator = makeCoordinator(probe: probe)

        let reply = coordinator.applicationShouldTerminate(.shared)

        XCTAssertEqual(reply, .terminateNow)
        XCTAssertFalse(coordinator.showsQuitConfirmation)
        XCTAssertTrue(probe.replies.isEmpty)
    }

    @MainActor
    func test_termination_waits_for_confirmation_during_an_active_operation() {
        let probe = Probe()
        probe.hasActiveOperations = true
        let coordinator = makeCoordinator(probe: probe)

        let reply = coordinator.applicationShouldTerminate(.shared)

        XCTAssertEqual(reply, .terminateLater)
        XCTAssertTrue(coordinator.showsQuitConfirmation)
    }

    @MainActor
    func test_keep_running_cancels_a_pending_termination() {
        let probe = Probe()
        probe.hasActiveOperations = true
        let coordinator = makeCoordinator(probe: probe)
        _ = coordinator.applicationShouldTerminate(.shared)

        coordinator.keepRunning()

        XCTAssertEqual(probe.replies, [false])
        XCTAssertFalse(coordinator.showsQuitConfirmation)
    }

    @MainActor
    func test_confirmation_completes_a_pending_termination() {
        let probe = Probe()
        probe.hasActiveOperations = true
        let coordinator = makeCoordinator(probe: probe)
        _ = coordinator.applicationShouldTerminate(.shared)

        coordinator.confirmTermination()

        XCTAssertEqual(probe.replies, [true])
        XCTAssertFalse(coordinator.showsQuitConfirmation)
    }
}
