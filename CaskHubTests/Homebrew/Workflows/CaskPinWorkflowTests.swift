//
//  CaskPinWorkflowTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 15/11/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class CaskPinWorkflowTests: XCTestCase {
    private let runner = StubBrewProcessRunner()
    private let scanner = MutableInstalledSoftwareScanner()

    private func makeService() -> LocalHomebrewService {
        let service = makeMutationService(runner: runner, scanner: scanner)
        runner.onRequest = { [scanner] request in
            let pins: [String: String] = request.arguments.first == "pin" ? ["zed": "1.0"] : [:]
            scanner.replace(with: InstallationSnapshot(pinnedVersions: pins))
        }
        return service
    }

    private var arguments: [[String]] {
        runner.requests.map(\.arguments)
    }

    func test_pin_runs_brew_pin_and_publishes_the_rescanned_pin() async throws {
        let service = makeService()

        try await service.setPinned(true, reference: "zed")

        XCTAssertEqual(arguments, [["pin", "--cask", "zed"]])
        XCTAssertEqual(runner.requests.first?.environment["HOMEBREW_NO_ASK"], "1")
        XCTAssertEqual(service.pinnedVersion(for: "zed"), "1.0")
        XCTAssertTrue(service.pinChangesInFlight.isEmpty)
    }

    func test_unpin_runs_brew_unpin_and_clears_the_pin() async throws {
        let service = makeService()
        try await service.setPinned(true, reference: "zed")

        try await service.setPinned(false, reference: "zed")

        XCTAssertEqual(arguments.last, ["unpin", "--cask", "zed"])
        XCTAssertNil(service.pinnedVersion(for: "zed"))
    }

    func test_tap_cask_pin_uses_the_full_reference() async throws {
        let service = makeService()

        try await service.setPinned(true, reference: "acme/tools/zed")

        XCTAssertEqual(arguments, [["pin", "--cask", "acme/tools/zed"]])
        XCTAssertEqual(service.pinnedVersion(for: "acme/tools/zed"), "1.0")
    }

    func test_failed_pin_throws_and_clears_in_flight() async {
        let service = makeService()
        runner.queuedResults = [BrewProcessResult(exitCode: 1, output: "Error: zed is not installed")]

        do {
            try await service.setPinned(true, reference: "zed")
            XCTFail("Expected the failed pin to throw")
        } catch {
            XCTAssertTrue(error is LocalHomebrewError)
        }
        XCTAssertTrue(service.pinChangesInFlight.isEmpty)
    }

    func test_pin_is_ignored_while_the_cask_has_an_active_operation() async throws {
        let service = makeService()
        service.operationStore.send(.enqueue(.updating), for: "zed")

        try await service.setPinned(true, reference: "zed")

        XCTAssertTrue(arguments.isEmpty)
    }

    func test_pinning_support_follows_the_homebrew_version() async {
        for (version, expected) in [
            ("5.1.11", false), ("5.1.12", true), ("7.0.13-140-g1cd7b3e", true), ("test", true), (nil, true)
        ] as [(String?, Bool)] {
            let service = LocalHomebrewService(defaults: makeScratchDefaults("pin-version-\(UUID().uuidString)")) {
                $0.softwareScanner = EmptyInstalledSoftwareScanner()
                $0.brewBinaryProvider = { nil }
                $0.caskPlatformProvider = { nil }
                $0.brewVersionProvider = { version }
            }
            await service.refresh()
            XCTAssertEqual(service.supportsCaskPinning, expected, "Homebrew \(version ?? "nil")")
        }
    }
}
