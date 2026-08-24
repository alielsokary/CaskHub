//
//  CaskOperationStateTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 25/07/2026.
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

    func test_enqueue_is_only_accepted_from_idle_or_failure() {
        for fixture in stateFixtures {
            let expected: CaskOperationState? = switch fixture.state {
            case nil, .failed:
                .queued(.updating)
            default:
                fixture.state
            }
            let result = CaskOperationStateMachine.transition(
                from: fixture.state,
                on: .enqueue(.updating)
            )

            XCTAssertEqual(result, expected, fixture.name)
        }
    }

    func test_begin_is_accepted_from_every_state_except_running() {
        let progress = makeProgress(action: .updating)
        let expectedRunning = CaskOperationState.running(
            progress: progress,
            canCancel: false,
            cancellationRequested: false
        )

        for fixture in stateFixtures {
            let expected = fixture.state?.progress == nil
                ? expectedRunning
                : fixture.state
            let result = CaskOperationStateMachine.transition(
                from: fixture.state,
                on: .begin(progress, canCancel: false)
            )

            XCTAssertEqual(result, expected, fixture.name)
        }
    }

    func test_progress_update_preserves_running_flags() {
        let initial = runningState(
            canCancel: true,
            cancellationRequested: false
        )
        let updatedProgress = makeProgress(
            action: .installing,
            phase: .downloading
        )
        let result = CaskOperationStateMachine.transition(
            from: initial,
            on: .updateProgress(updatedProgress)
        )

        XCTAssertEqual(result?.progress, updatedProgress)
        XCTAssertTrue(result?.canCancel == true)
        XCTAssertFalse(result?.cancellationRequested == true)
    }

    func test_progress_update_requires_the_same_token_and_action() {
        let initial = runningState(canCancel: true)
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

    func test_progress_update_is_ignored_outside_running_state() {
        for fixture in nonRunningStateFixtures {
            let result = CaskOperationStateMachine.transition(
                from: fixture.state,
                on: .updateProgress(makeProgress(action: .installing))
            )

            XCTAssertEqual(result, fixture.state, fixture.name)
        }
    }

    func test_set_cancellable_only_changes_running_state() {
        for fixture in nonRunningStateFixtures {
            let result = CaskOperationStateMachine.transition(
                from: fixture.state,
                on: .setCancellable(true)
            )

            XCTAssertEqual(result, fixture.state, fixture.name)
        }

        let running = runningState(canCancel: false)
        let cancellable = CaskOperationStateMachine.transition(
            from: running,
            on: .setCancellable(true)
        )

        XCTAssertTrue(cancellable?.canCancel == true)
    }

    func test_set_cancellable_cannot_reenable_requested_cancellation() {
        let canceling = runningState(
            canCancel: false,
            cancellationRequested: true
        )
        let result = CaskOperationStateMachine.transition(
            from: canceling,
            on: .setCancellable(true)
        )

        XCTAssertEqual(result, canceling)
        XCTAssertFalse(result?.canCancel == true)
        XCTAssertTrue(result?.cancellationRequested == true)
    }

    func test_request_cancellation_is_one_legal_transition() {
        let running = runningState(
            canCancel: true,
            phase: .downloading
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
        let running = runningState(canCancel: false)

        XCTAssertEqual(
            CaskOperationStateMachine.transition(
                from: running,
                on: .requestCancellation
            ),
            running
        )
    }

    func test_request_cancellation_is_ignored_outside_running_state() {
        for fixture in nonRunningStateFixtures {
            let result = CaskOperationStateMachine.transition(
                from: fixture.state,
                on: .requestCancellation
            )

            XCTAssertEqual(result, fixture.state, fixture.name)
        }
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

    func test_unconditional_events_replace_every_state() {
        for fixture in stateFixtures {
            assertUnconditionalEventsReplace(fixture)
        }
    }

    private var stateFixtures: [(name: String, state: CaskOperationState?)] {
        nonRunningStateFixtures + [
            (
                "running",
                runningState(canCancel: true)
            )
        ]
    }

    private var nonRunningStateFixtures:
        [(name: String, state: CaskOperationState?)] {
        [
            ("idle", nil),
            ("queued", .queued(.installing)),
            ("awaiting permission", .awaitingPermission(sampleAdoptionRequest)),
            ("awaiting adoption", .awaitingAdoption(sampleAdoptionRequest)),
            ("failed", .failed(sampleFailure))
        ]
    }

    private var sampleFailure: CaskOperationFailure {
        CaskOperationFailure(
            kind: .brewCommand,
            message: "failed"
        )
    }

    private var sampleAdoptionRequest: CaskAdoptionRequest {
        let cask = Cask.preview(token: "sample", version: "1.0")
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

    private func assertUnconditionalEventsReplace(
        _ fixture: (name: String, state: CaskOperationState?)
    ) {
        XCTAssertEqual(
            CaskOperationStateMachine.transition(
                from: fixture.state,
                on: .awaitPermission(sampleAdoptionRequest)
            ),
            .awaitingPermission(sampleAdoptionRequest),
            fixture.name
        )
        XCTAssertEqual(
            CaskOperationStateMachine.transition(
                from: fixture.state,
                on: .awaitAdoption(sampleAdoptionRequest)
            ),
            .awaitingAdoption(sampleAdoptionRequest),
            fixture.name
        )
        XCTAssertEqual(
            CaskOperationStateMachine.transition(
                from: fixture.state,
                on: .fail(sampleFailure)
            ),
            .failed(sampleFailure),
            fixture.name
        )
        XCTAssertNil(
            CaskOperationStateMachine.transition(
                from: fixture.state,
                on: .clear
            ),
            fixture.name
        )
    }

    private func runningState(
        canCancel: Bool,
        cancellationRequested: Bool = false,
        phase: CaskOperationPhase = .preparing
    ) -> CaskOperationState {
        .running(
            progress: makeProgress(action: .installing, phase: phase),
            canCancel: canCancel,
            cancellationRequested: cancellationRequested
        )
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
