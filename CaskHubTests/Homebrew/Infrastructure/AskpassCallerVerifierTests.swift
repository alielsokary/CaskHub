//
//  AskpassCallerVerifierTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 06/11/2026.
//

@testable import CaskHub
import XCTest

final class AskpassCallerVerifierTests: XCTestCase {
    private let app = "/Applications/CaskHub.app/Contents/MacOS/CaskHub"

    func test_accepts_askpass_launched_through_brew_and_sudo_by_caskhub() {
        let tree: [pid_t: (parent: pid_t, path: String)] = [
            40: (30, "/usr/bin/sudo"),
            30: (20, "/opt/homebrew/Library/Homebrew/vendor/portable-ruby/bin/ruby"),
            20: (10, app),
            10: (1, "/sbin/launchd")
        ]
        XCTAssertTrue(verify(startingAt: 40, ownPID: 50, tree: tree))
    }

    func test_rejects_askpass_run_by_another_process() {
        let tree: [pid_t: (parent: pid_t, path: String)] = [
            40: (30, "/bin/zsh"),
            30: (1, "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
        ]
        XCTAssertFalse(verify(startingAt: 40, ownPID: 50, tree: tree))
    }

    func test_ignores_itself_and_stops_on_unknown_parents() {
        XCTAssertFalse(verify(startingAt: 50, ownPID: 50, tree: [50: (1, app)]))
        XCTAssertFalse(verify(startingAt: 40, ownPID: 50, tree: [:]))
    }

    func test_live_process_tree_resolves_parent_and_path() {
        XCTAssertEqual(AskpassCallerVerifier.parent(of: getpid()), getppid())
        XCTAssertEqual(
            AskpassCallerVerifier.executablePath(of: getpid()),
            Bundle.main.executableURL?.resolvingSymlinksInPath().path
        )
    }

    private func verify(startingAt pid: pid_t, ownPID: pid_t, tree: [pid_t: (parent: pid_t, path: String)]) -> Bool {
        AskpassCallerVerifier.isLaunchedByCaskHub(
            startingAt: pid,
            ownPID: ownPID,
            ownPath: app,
            parent: { tree[$0]?.parent },
            executablePath: { tree[$0]?.path }
        )
    }
}
