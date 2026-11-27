//
//  StrandedCopyTelemetryTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 25/11/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class StrandedCopyTelemetryTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!
    private var spy: SpyCrashReporterProvider!
    private var savedProvider: CrashReporterProvider!
    private var savedIsRunningTests = false
    private var savedDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fileManager.temporaryDirectory.appendingPathComponent("stranded-telemetry-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: root.appendingPathComponent("Caskroom/zed/1.10.3/Zed.app"),
            withIntermediateDirectories: true
        )
        spy = SpyCrashReporterProvider()
        savedProvider = CrashReporter.provider
        savedIsRunningTests = CrashReporter.isRunningTests
        savedDefaults = CrashReporter.defaults
        CrashReporter.provider = spy
        CrashReporter.isRunningTests = false
        CrashReporter.captureCounts = [:]
        CrashReporter.defaults = makeScratchDefaults("stranded-telemetry-crash")
    }

    override func tearDownWithError() throws {
        CrashReporter.provider = savedProvider
        CrashReporter.isRunningTests = savedIsRunningTests
        CrashReporter.captureCounts = [:]
        CrashReporter.defaults = savedDefaults
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    func test_failure_that_leaves_a_stranded_copy_is_tagged_and_reported_on_its_own() async {
        await upgradeZed(failingWith: "Error: It seems the App source '/Applications/Zed.app' is not there.")

        let stranded = spy.capturedErrors.compactMap { $0 as? StrandedCopyDetected }
        XCTAssertEqual(stranded.map(\.failureKind), [.missingArtifactSource])
        XCTAssertEqual(stranded.map(\.subcommand), ["upgrade"])
        XCTAssertEqual(spy.capturedErrors.count, 2)
        XCTAssertTrue(spy.capturedErrorTags.allSatisfy { $0["brew.left_stranded_copy"] == "true" })
    }

    func test_failure_about_an_existing_stranded_copy_is_not_a_new_stranding() async {
        await upgradeZed(failingWith: "Error: It seems there is already an App at '\(root.path)/Caskroom/zed/1.10.3/Zed.app'.")

        XCTAssertFalse(spy.capturedErrors.contains { $0 is StrandedCopyDetected })
        XCTAssertEqual(spy.capturedErrors.count, 1)
        XCTAssertNil(spy.capturedErrorTags.last?["brew.left_stranded_copy"])
    }

    private func upgradeZed(failingWith output: String) async {
        let runner = StubBrewProcessRunner()
        runner.queuedResults = [.success, BrewProcessResult(exitCode: 1, output: output)]
        let defaults = makeScratchDefaults("stranded-telemetry-\(UUID().uuidString)")
        defaults.set(root.path, forKey: HomebrewLocator.customPrefixKey)
        let service = LocalHomebrewService(defaults: defaults) {
            $0.fileManager = fileManager
            $0.applicationDirectories = [root.appendingPathComponent("Applications")]
            $0.processRunner = runner
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
            $0.askpassProvider = { URL(fileURLWithPath: "/private/tmp/caskhub-test-askpass-\($0)") }
        }
        try? await service.upgrade(token: "zed")
    }
}
