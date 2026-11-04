//
//  ApplicationDirectoryTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 03/11/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class ApplicationDirectoryTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!
    private var systemApps: URL!
    private var userApps: URL!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fileManager.temporaryDirectory
            .appendingPathComponent("application-directory-\(UUID().uuidString)")
            .standardizedFileURL
        systemApps = root.appendingPathComponent("Applications")
        userApps = root.appendingPathComponent("UserApps")
        try fileManager.createDirectory(at: systemApps, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: userApps, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: root.appendingPathComponent("Caskroom/zed/1.0"),
            withIntermediateDirectories: true
        )
        defaults = makeScratchDefaults("application-directory-\(UUID().uuidString)")
        defaults.set(root.path, forKey: HomebrewLocator.customPrefixKey)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func makeService(runner: StubBrewProcessRunner) -> LocalHomebrewService {
        let service = LocalHomebrewService(defaults: defaults) {
            $0.fileManager = fileManager
            $0.applicationDirectories = [systemApps]
            $0.processRunner = runner
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
        }
        service.fullDiskAccessProbe = { .granted }
        service.permissionProbe = { _ in
            AppManagementPermission.Assessment(status: .granted, evidence: .target)
        }
        return service
    }

    func test_install_targets_the_chosen_directory_and_default_passes_no_flag() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeService(runner: runner)

        await service.setApplicationDirectory(userApps)
        try await service.install(token: "zed")

        XCTAssertEqual(runner.requests.last?.arguments, ["install", "--cask", "zed", "--appdir=\(userApps.path)"])
        XCTAssertEqual(service.applicationDirectories.map(\.path), [systemApps.path, userApps.path])
        XCTAssertEqual(makeService(runner: runner).applicationDirectoryOverride?.path, userApps.path)

        await service.setApplicationDirectory(URL(fileURLWithPath: "/Applications/"))
        try await service.install(token: "zed")

        XCTAssertNil(service.applicationDirectoryOverride)
        XCTAssertEqual(runner.requests.last?.arguments, ["install", "--cask", "zed"])
        XCTAssertEqual(service.applicationDirectories.map(\.path), [systemApps.path])
    }

    func test_reinstall_keeps_the_existing_app_folder_over_the_setting() async throws {
        try makeApplicationBundle(in: systemApps, named: "Zed.app", bundleIdentifier: "dev.zed.Zed")
        let runner = StubBrewProcessRunner()
        let service = makeService(runner: runner)
        await service.setApplicationDirectory(userApps)
        updateInstalledCask(
            LocalCaskInstallation(
                token: "zed", installedVersion: "1.0", installedAt: nil,
                appBundleNames: ["Zed.app"], tap: "homebrew/cask"
            ),
            in: service
        )

        try await service.repairReinstalling(token: "zed")

        XCTAssertEqual(runner.requests.last?.arguments, ["install", "--cask", "zed", "--appdir=\(systemApps.path)"])
    }

    func test_adoption_runs_in_the_folder_holding_the_app() async throws {
        let appURL = try makeApplicationBundle(
            in: systemApps, named: "Sample.app", bundleIdentifier: "com.example.sample"
        )
        let runner = StubBrewProcessRunner()
        let service = makeService(runner: runner)
        await service.setApplicationDirectory(userApps)
        let cask = makeCask("sample", appNames: ["Sample.app"])
        seedExternalInstallation(of: cask, version: "1.0", url: appURL, in: service)

        await service.requestAdoption(cask)
        let request = try XCTUnwrap(service.operationStore.state(for: "sample")?.adoptionRequest)
        try await service.confirmAdoption(request)

        XCTAssertEqual(
            runner.requests.map(\.arguments),
            [["install", "--cask", "sample", "--adopt", "--appdir=\(systemApps.path)"]]
        )
    }
}
