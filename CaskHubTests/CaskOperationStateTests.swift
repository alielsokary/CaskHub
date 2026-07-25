//
//  CaskOperationStateTests.swift
//  CaskHubTests
//

@testable import CaskHub
import XCTest

final class CaskOperationStateTests: XCTestCase {
    func test_enqueue_then_begin_enters_running_state() {
        let queued = CaskOperationStateMachine.transition(
            from: nil,
            on: .enqueue(.installing)
        )
        let progress = makeProgress(action: .installing)
        let running = CaskOperationStateMachine.transition(
            from: queued,
            on: .begin(progress, canCancel: true)
        )

        XCTAssertEqual(queued, .queued(.installing))
        XCTAssertEqual(running?.progress, progress)
        XCTAssertEqual(running?.action, .installing)
        XCTAssertTrue(running?.canCancel == true)
        XCTAssertFalse(running?.cancellationRequested == true)
    }

    func test_begin_does_not_replace_an_existing_running_operation() {
        let installing = CaskOperationState.running(
            progress: makeProgress(action: .installing),
            canCancel: true,
            cancellationRequested: false
        )

        let result = CaskOperationStateMachine.transition(
            from: installing,
            on: .begin(makeProgress(action: .updating), canCancel: false)
        )

        XCTAssertEqual(result, installing)
    }

    func test_progress_update_requires_the_same_token_and_action() {
        let initial = CaskOperationState.running(
            progress: makeProgress(action: .installing),
            canCancel: true,
            cancellationRequested: false
        )
        let wrongToken = CaskOperationProgress(
            token: "other",
            displayName: "Other",
            action: .installing,
            phase: .downloading
        )
        let wrongAction = makeProgress(action: .updating, phase: .downloading)

        XCTAssertEqual(
            CaskOperationStateMachine.transition(
                from: initial,
                on: .updateProgress(wrongToken)
            ),
            initial
        )
        XCTAssertEqual(
            CaskOperationStateMachine.transition(
                from: initial,
                on: .updateProgress(wrongAction)
            ),
            initial
        )
    }

    func test_request_cancellation_is_one_legal_transition() {
        let running = CaskOperationState.running(
            progress: makeProgress(action: .installing, phase: .downloading),
            canCancel: true,
            cancellationRequested: false
        )

        let canceling = CaskOperationStateMachine.transition(
            from: running,
            on: .requestCancellation
        )
        let repeated = CaskOperationStateMachine.transition(
            from: canceling,
            on: .requestCancellation
        )

        XCTAssertEqual(canceling?.progress?.phase, .canceling)
        XCTAssertFalse(canceling?.canCancel == true)
        XCTAssertTrue(canceling?.cancellationRequested == true)
        XCTAssertEqual(repeated, canceling)
    }

    func test_non_cancellable_operation_ignores_cancellation() {
        let running = CaskOperationState.running(
            progress: makeProgress(action: .repairing),
            canCancel: false,
            cancellationRequested: false
        )

        XCTAssertEqual(
            CaskOperationStateMachine.transition(
                from: running,
                on: .requestCancellation
            ),
            running
        )
    }

    func test_failure_keeps_one_typed_set_of_recovery_actions() {
        let failure = CaskOperationFailure(
            kind: .appManagementDenied,
            message: "Operation not permitted",
            recoveries: [.openAppManagementSettings, .repairAndReinstall]
        )
        let state = CaskOperationStateMachine.transition(
            from: nil,
            on: .fail(failure)
        )

        XCTAssertEqual(state?.failure, failure)
        XCTAssertEqual(
            state?.failure?.recoveries,
            [.openAppManagementSettings, .repairAndReinstall]
        )
    }

    func test_confirmation_states_replace_transient_operation_state() {
        let running = CaskOperationState.running(
            progress: makeProgress(action: .adopting),
            canCancel: false,
            cancellationRequested: false
        )

        XCTAssertEqual(
            CaskOperationStateMachine.transition(
                from: running,
                on: .awaitPermission(force: true)
            ),
            .awaitingPermission(force: true)
        )
        XCTAssertEqual(
            CaskOperationStateMachine.transition(
                from: running,
                on: .awaitPackageAdoption
            ),
            .awaitingPackageAdoption
        )
    }

    func test_clear_returns_to_implicit_idle_state() {
        let failed = CaskOperationState.failed(CaskOperationFailure(
            kind: .brewCommand,
            message: "failed"
        ))

        XCTAssertNil(CaskOperationStateMachine.transition(from: failed, on: .clear))
    }

    private func makeProgress(
        action: CaskAction,
        phase: CaskOperationPhase = .preparing
    ) -> CaskOperationProgress {
        CaskOperationProgress(
            token: "firefox",
            displayName: "Firefox",
            action: action,
            phase: phase
        )
    }
}
