//
//  CaskActionPresentationTests.swift
//  CaskHubTests
//

@testable import CaskHub
import XCTest

@MainActor
final class CaskActionPresentationTests: XCTestCase {
    func test_running_presentation_exposes_one_coherent_operation() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("presentation-running"))
        let cask = makeCask("firefox", name: "Firefox")
        service.beginOperation(.installing, token: cask.token)
        service.operationStore.send(.setCancellable(true), for: cask.token)

        let presentation = service.actionPresentation(for: cask)

        XCTAssertEqual(presentation.activeAction, .installing)
        XCTAssertEqual(presentation.progress?.token, cask.token)
        XCTAssertTrue(presentation.canCancel)
        XCTAssertTrue(presentation.isBusy)
        XCTAssertNil(presentation.alert)
    }

    func test_failure_presentation_carries_message_and_recovery_together() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("presentation-failure"))
        let cask = makeCask("tabby")
        let failure = CaskOperationFailure(
            kind: .brewCommand,
            message: "Repair is available",
            recoveries: [.repairAndReinstall]
        )
        service.operationStore.send(.fail(failure), for: cask.token)

        let presentation = service.actionPresentation(for: cask)

        XCTAssertEqual(presentation.alert, .failure(failure))
        XCTAssertFalse(presentation.isBusy)
        XCTAssertNil(presentation.activeAction)
    }

    func test_homebrew_missing_has_a_distinct_alert() {
        let service = LocalHomebrewService(defaults: makeScratchDefaults("presentation-brew"))
        let cask = makeCask("firefox")
        let failure = CaskOperationFailure(
            kind: .homebrewMissing,
            message: "Homebrew not found"
        )
        service.operationStore.send(.fail(failure), for: cask.token)

        XCTAssertEqual(
            service.actionPresentation(for: cask).alert,
            .homebrewMissing(message: "Homebrew not found")
        )
    }
}
