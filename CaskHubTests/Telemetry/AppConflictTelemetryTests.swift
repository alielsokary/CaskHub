//
//  AppConflictTelemetryTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 27/11/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class AppConflictTelemetryTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!
    private var spy: SpyCrashReporterProvider!
    private var savedProvider: CrashReporterProvider!
    private var savedIsRunningTests = false
    private var savedDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fileManager.temporaryDirectory.appendingPathComponent("conflict-telemetry-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root.appendingPathComponent("Caskroom"), withIntermediateDirectories: true)
        spy = SpyCrashReporterProvider()
        savedProvider = CrashReporter.provider
        savedIsRunningTests = CrashReporter.isRunningTests
        savedDefaults = CrashReporter.defaults
        CrashReporter.provider = spy
        CrashReporter.isRunningTests = false
        CrashReporter.defaults = makeScratchDefaults("conflict-telemetry-crash")
    }

    override func tearDownWithError() throws {
        CrashReporter.provider = savedProvider
        CrashReporter.isRunningTests = savedIsRunningTests
        CrashReporter.captureCounts = [:]
        CrashReporter.defaults = savedDefaults
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    func test_app_conflict_tags_what_already_occupies_the_apps_path() async throws {
        let apps = root.appendingPathComponent("Applications")
        try makeApplicationBundle(in: apps, named: "Same.app", bundleIdentifier: "com.example.same")
        try makeApplicationBundle(in: apps, named: "Other.app", bundleIdentifier: "org.unrelated.other")
        try makeApplicationBundle(in: apps, named: "Hinted.app", bundleIdentifier: "org.vendor.hinted")
        let mobile = apps.appendingPathComponent("Mobile.app")
        try fileManager.createDirectory(at: mobile.appendingPathComponent("Wrapper/Mobile.app"), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            atPath: mobile.appendingPathComponent("WrappedBundle").path, withDestinationPath: "Wrapper/Mobile.app"
        )

        for (token, app, occupant) in [
            ("same", "Same.app", "same-identifier"), ("other", "Other.app", "other-identifier"),
            ("hinted", "Hinted.app", "same-identifier"),
            ("mobile", "Mobile.app", "iphone-ipad-app"), ("gone", "Gone.app", "unreadable")
        ] {
            let tags = try await installTags(token, conflictingWith: apps.appendingPathComponent(app))
            XCTAssertEqual(tags?["brew.conflict_occupant"], occupant, token)
        }
    }

    private func installTags(_ token: String, conflictingWith app: URL) async throws -> [String: String]? {
        CrashReporter.captureCounts = [:]
        let runner = StubBrewProcessRunner()
        let defaults = makeScratchDefaults("conflict-telemetry-\(UUID().uuidString)")
        defaults.set(root.path, forKey: HomebrewLocator.customPrefixKey)
        let service = LocalHomebrewService(defaults: defaults) {
            $0.fileManager = fileManager
            $0.applicationDirectories = [root.appendingPathComponent("Applications")]
            $0.processRunner = runner
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
            $0.askpassProvider = { URL(fileURLWithPath: "/private/tmp/caskhub-test-askpass-\($0)") }
        }
        var cask = makeCask(token, appNames: [app.lastPathComponent], applicationBundleIdentifiers: ["com.example.\(token)"])
        let zap = #"{"zap":[{"trash":"~/Library/Preferences/org.vendor.hinted.plist"}]}"#
        cask.artifacts?.append(try JSONDecoder().decode(ArtifactStanza.self, from: Data(zap.utf8)))
        await service.updatePackageCatalog([cask])
        runner.queuedResults = [
            .success, BrewProcessResult(exitCode: 1, output: "Error: It seems there is already an App at '\(app.path)'.")
        ]
        try? await service.install(token: token)
        return spy.capturedErrorTags.last
    }
}
