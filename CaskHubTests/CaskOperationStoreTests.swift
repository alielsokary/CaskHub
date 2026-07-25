//
//  CaskOperationStoreTests.swift
//  CaskHubTests
//

@testable import CaskHub
import XCTest

@MainActor
final class CaskOperationStoreTests: XCTestCase {
    func test_store_projects_running_state_without_parallel_mutable_collections() {
        let store = CaskOperationStore()
        let progress = CaskOperationProgress(
            token: "firefox",
            displayName: "Firefox",
            action: .installing,
            phase: .preparing
        )

        store.send(.begin(progress, canCancel: false), for: "firefox")
        store.send(.setCancellable(true), for: "firefox")

        XCTAssertEqual(store.inFlightActions, ["firefox": .installing])
        XCTAssertEqual(store.operationProgress, ["firefox": progress])
        XCTAssertEqual(store.cancellableTokens, ["firefox"])
        XCTAssertTrue(store.failures.isEmpty)
    }

    func test_store_projects_confirmation_states() {
        let store = CaskOperationStore()

        store.send(.awaitPermission(force: true), for: "canva")
        store.send(.awaitPackageAdoption, for: "zoom")

        XCTAssertEqual(store.pendingPermissions, ["canva": true])
        XCTAssertEqual(store.pendingPackageAdoptions, ["zoom"])
        XCTAssertTrue(store.inFlightActions.isEmpty)
    }

    func test_store_projects_failure_and_recovery_options() {
        let store = CaskOperationStore()
        let failure = CaskOperationFailure(
            kind: .brewCommand,
            message: "failed",
            recoveries: [.repairAndReinstall, .openAppManagementSettings]
        )

        store.send(.fail(failure), for: "tabby")

        XCTAssertEqual(store.failures["tabby"], failure)
        XCTAssertEqual(store.tokens(offering: .repairAndReinstall), ["tabby"])
        XCTAssertEqual(store.tokens(offering: .openAppManagementSettings), ["tabby"])
        XCTAssertTrue(store.tokens(offering: .replaceWithHomebrew).isEmpty)
    }

    func test_store_ignores_duplicate_transitions() {
        let store = CaskOperationStore()
        store.send(.enqueue(.updating), for: "firefox")
        store.send(.enqueue(.installing), for: "firefox")

        XCTAssertEqual(store.state(for: "firefox"), .queued(.updating))
    }

    func test_status_is_derived_from_operation_state() {
        let store = CaskOperationStore()
        let progress = CaskOperationProgress(
            token: "firefox",
            displayName: "Firefox",
            action: .updating,
            phase: .performing
        )

        store.send(.begin(progress, canCancel: false), for: "firefox")

        XCTAssertEqual(store.status?.message, "Updating Firefox…")
    }
}
