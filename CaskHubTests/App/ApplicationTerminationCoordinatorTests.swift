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
        var confirmationResult = false
        var confirmationCount = 0
    }

    @MainActor
    private func makeCoordinator(
        probe: Probe
    ) -> ApplicationTerminationCoordinator {
        ApplicationTerminationCoordinator(
            hasActiveOperations: { probe.hasActiveOperations },
            requestApplicationTermination: { probe.requestCount += 1 },
            presentQuitConfirmation: {
                probe.confirmationCount += 1
                return probe.confirmationResult
            }
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
        XCTAssertEqual(probe.confirmationCount, 0)
    }

    @MainActor
    func test_termination_is_cancelled_when_the_user_keeps_an_active_operation_running() {
        let probe = Probe()
        probe.hasActiveOperations = true
        let coordinator = makeCoordinator(probe: probe)

        let reply = coordinator.applicationShouldTerminate(.shared)

        XCTAssertEqual(reply, .terminateCancel)
        XCTAssertEqual(probe.confirmationCount, 1)
    }

    @MainActor
    func test_termination_proceeds_when_the_user_confirms_during_an_active_operation() {
        let probe = Probe()
        probe.hasActiveOperations = true
        probe.confirmationResult = true
        let coordinator = makeCoordinator(probe: probe)

        let reply = coordinator.applicationShouldTerminate(.shared)

        XCTAssertEqual(reply, .terminateNow)
        XCTAssertEqual(probe.confirmationCount, 1)
    }

    @MainActor
    func test_configured_operation_provider_is_used_after_launch() {
        let probe = Probe()
        let coordinator = ApplicationTerminationCoordinator(
            hasActiveOperations: { false },
            requestApplicationTermination: {},
            presentQuitConfirmation: {
                probe.confirmationCount += 1
                return false
            }
        )
        coordinator.configure {
            true
        }

        let reply = coordinator.applicationShouldTerminate(.shared)

        XCTAssertEqual(reply, .terminateCancel)
        XCTAssertEqual(probe.confirmationCount, 1)
    }
}
