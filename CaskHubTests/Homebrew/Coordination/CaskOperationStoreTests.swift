//
//  CaskOperationStoreTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 25/07/2026.
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

        let state = store.state(for: "firefox")
        XCTAssertEqual(state?.action, .installing)
        XCTAssertEqual(state?.progress, progress)
        XCTAssertTrue(state?.canCancel == true)
        XCTAssertNil(state?.failure)
    }

    func test_store_projects_confirmation_states() {
        let store = CaskOperationStore()
        let request = adoptionRequest()

        store.send(.awaitPermission(request), for: "canva")
        store.send(.awaitAdoption(request), for: "zoom")

        XCTAssertEqual(store.pendingPermissions, ["canva": request])
        XCTAssertEqual(store.state(for: "zoom"), .awaitingAdoption(request))
        XCTAssertNil(store.state(for: "canva")?.action)
        XCTAssertNil(store.state(for: "zoom")?.action)
    }

    func test_store_projects_failure_and_recovery_options() {
        let store = CaskOperationStore()
        let failure = CaskOperationFailure(
            kind: .brewCommand,
            message: "failed",
            recoveries: [.repairAndReinstall, .openAppManagementSettings]
        )

        store.send(.fail(failure), for: "tabby")

        let storedFailure = store.state(for: "tabby")?.failure
        XCTAssertEqual(storedFailure, failure)
        XCTAssertTrue(storedFailure?.recoveries.contains(.repairAndReinstall) == true)
        XCTAssertTrue(storedFailure?.recoveries.contains(.openAppManagementSettings) == true)
        XCTAssertFalse(storedFailure?.recoveries.contains(.replaceWithHomebrew) == true)
    }

    func test_store_ignores_duplicate_transitions() {
        let store = CaskOperationStore()
        store.send(.enqueue(.updating), for: "firefox")
        store.send(.enqueue(.installing), for: "firefox")

        XCTAssertEqual(store.state(for: "firefox"), .queued(.updating))
    }

    func test_active_operations_include_queued_and_running_work() {
        let store = CaskOperationStore()
        let progress = CaskOperationProgress(
            token: "zoom",
            displayName: "Zoom",
            action: .uninstalling,
            phase: .performing
        )

        XCTAssertFalse(store.hasActiveOperations)

        store.send(.enqueue(.installing), for: "firefox")
        XCTAssertTrue(store.hasActiveOperations)

        store.send(.begin(progress, canCancel: false), for: "zoom")
        XCTAssertTrue(store.hasActiveOperations)

        store.send(.clear, for: "firefox")
        store.send(.clear, for: "zoom")
        XCTAssertFalse(store.hasActiveOperations)
    }

    func test_confirmation_and_failure_states_are_not_active_operations() {
        let store = CaskOperationStore()
        let failure = CaskOperationFailure(kind: .brewCommand, message: "failed")
        let request = adoptionRequest()

        store.send(.awaitPermission(request), for: "canva")
        store.send(.awaitAdoption(request), for: "zoom")
        store.send(.fail(failure), for: "tabby")

        XCTAssertFalse(store.hasActiveOperations)
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

        let updatingLabel = CaskOperationPhase.performing.label(for: .updating)
        XCTAssertEqual(store.status?.message, "\(updatingLabel) Firefox…")
    }

    func test_update_all_lifecycle_has_one_owner_and_clears_progress_atomically() {
        let store = CaskOperationStore()
        let progress = CaskUpdateAllProgress(
            currentIndex: 1,
            totalCount: 2,
            currentToken: "firefox",
            currentDisplayName: "Firefox"
        )

        XCTAssertTrue(store.beginUpdateAll())
        XCTAssertFalse(store.beginUpdateAll())
        XCTAssertTrue(store.hasActiveOperations)

        store.setUpdateAllProgress(progress)
        XCTAssertTrue(store.isUpdatingAll)
        XCTAssertEqual(store.updateAllProgress, progress)

        store.finishUpdateAll()
        XCTAssertFalse(store.isUpdatingAll)
        XCTAssertNil(store.updateAllProgress)
        XCTAssertFalse(store.hasActiveOperations)
    }

    func test_update_all_progress_is_ignored_outside_an_active_batch() {
        let store = CaskOperationStore()
        let progress = CaskUpdateAllProgress(
            currentIndex: 1,
            totalCount: 1,
            currentToken: "firefox",
            currentDisplayName: "Firefox"
        )

        store.setUpdateAllProgress(progress)

        XCTAssertNil(store.updateAllProgress)
        XCTAssertFalse(store.isUpdatingAll)
    }

    private func adoptionRequest() -> CaskAdoptionRequest {
        let cask = makeCask("sample", appNames: ["Sample.app"])
        return CaskAdoptionRequest(
            cask: cask,
            intent: .planned,
            plan: CaskAdoptionPlan(
                artifact: .applicationBundle,
                versionRelationship: .same,
                operation: .adopt,
                execution: .adoptApplication,
                installedVersion: "1.0",
                homebrewVersion: "1.0",
                blockingInstalledCask: nil
            )
        )
    }
}
