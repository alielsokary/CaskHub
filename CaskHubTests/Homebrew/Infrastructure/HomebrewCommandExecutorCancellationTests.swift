//
//  HomebrewCommandExecutorCancellationTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 18/11/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class HomebrewCommandExecutorCancellationTests: XCTestCase {
    /// Stands in for brew 7.0.7+: curl runs in its own process group and brew's SIGINT handler
    /// forwards to that group, failing with EPERM when the group holds only an unreaped zombie.
    private let groupForwardingBrew = """
        $| = 1;
        my $pid = fork() // die;
        if ($pid == 0) { setpgrp(0, 0); exec('/bin/sleep', '30'); }
        setpgrp($pid, $pid);
        $SIG{INT} = sub { if (kill('INT', -$pid)) { exit(130) } print "Error: $!\\n"; exit(1) };
        print "ready $pid\\n";
        sleep 1 while 1;
        """

    func test_cancel_lets_brew_forward_the_interrupt_to_its_own_children() async throws {
        let executor = SystemHomebrewCommandExecutor()
        var childPID: Int32?
        let result = try await executor.execute(
            HomebrewCommandRequest(
                token: "mole-app",
                executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
                arguments: ["-e", groupForwardingBrew],
                environment: ProcessInfo.processInfo.environment
            ),
            onStart: {},
            onChunk: { chunk in
                guard childPID == nil,
                      let line = chunk.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("ready ") }),
                      let pid = Int32(line.dropFirst("ready ".count))
                else { return }
                childPID = pid
                XCTAssertTrue(executor.cancel(token: "mole-app"))
            }
        )

        XCTAssertNotNil(childPID)
        XCTAssertEqual(result.exitCode, 130, result.output)
        XCTAssertFalse(result.output.contains("Operation not permitted"))
        let child = try XCTUnwrap(childPID)
        // An orphaned child would keep sleeping for 30 seconds; a reaped one disappears at once.
        let deadline = Date.now.addingTimeInterval(2)
        while kill(child, 0) == 0, Date.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotEqual(kill(child, 0), 0, "the interrupted child must not outlive brew")
    }
}
