//
//  UninstallZapGateTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 13/10/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class UninstallZapGateTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fileManager.temporaryDirectory
            .appendingPathComponent("zap-gate-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: root.appendingPathComponent("Caskroom/zed/1.0"),
            withIntermediateDirectories: true
        )
        defaults = makeScratchDefaults("uninstall-zap-gate")
        defaults.set(root.path, forKey: HomebrewLocator.customPrefixKey)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
        defaults.removePersistentDomain(forName: "test.uninstall-zap-gate")
        try super.tearDownWithError()
    }

    private func makeService(runner: StubBrewProcessRunner) -> LocalHomebrewService {
        let service = LocalHomebrewService(defaults: defaults) {
            $0.fileManager = fileManager
            $0.applicationDirectories = [root.appendingPathComponent("Applications")]
            $0.processRunner = runner
            $0.softwareScanner = FixedInstalledSoftwareScanner(snapshot: .empty)
            $0.brewBinaryProvider = { URL(fileURLWithPath: "/test/bin/brew") }
            $0.brewVersionProvider = { "test" }
            $0.askpassProvider = {
                URL(fileURLWithPath: "/private/tmp/caskhub-test-askpass-\($0)")
            }
        }
        service.fullDiskAccessProbe = { .granted }
        updateInstalledCask(LocalCaskInstallation(
            token: "zed", installedVersion: "1.0", installedAt: nil,
            appBundleNames: ["Zed.app"]
        ), in: service)
        return service
    }

    private func strandApp(named name: String) throws {
        try fileManager.createDirectory(
            at: root.appendingPathComponent("Caskroom/zed/1.0/\(name)"),
            withIntermediateDirectories: true
        )
    }

    func test_uninstall_forces_past_a_copy_stranded_by_an_interrupted_uninstall() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeService(runner: runner)
        XCTAssertEqual(service.uninstallArguments(token: "zed", removingData: false), ["uninstall", "--cask", "zed"])

        try strandApp(named: "Zed.app")
        try await service.uninstall(token: "zed")

        XCTAssertEqual(runner.requests.map(\.arguments), [["uninstall", "--cask", "zed", "--force"]])
    }

    func test_zap_runs_unless_full_disk_access_is_proven_denied() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeService(runner: runner)
        service.setZapOnUninstall(true)
        let zap = ["uninstall", "--cask", "zed", "--zap"]

        XCTAssertFalse(service.zapBlockedByFullDiskAccess)
        XCTAssertEqual(service.uninstallArguments(token: "zed", removingData: true), zap)
        service.fullDiskAccessProbe = { .unknown }
        XCTAssertFalse(service.zapBlockedByFullDiskAccess)
        XCTAssertEqual(service.uninstallArguments(token: "zed", removingData: true), zap)

        service.fullDiskAccessProbe = { .denied }
        XCTAssertTrue(service.zapBlockedByFullDiskAccess)
        try await service.uninstall(token: "zed")

        XCTAssertEqual(runner.requests.map(\.arguments), [["uninstall", "--cask", "zed"]])
    }

    func test_keeping_data_never_zaps_even_when_full_disk_access_is_granted() async throws {
        let runner = StubBrewProcessRunner()
        let service = makeService(runner: runner)
        service.setZapOnUninstall(true)

        try await service.uninstallKeepingData(token: "zed")

        XCTAssertEqual(runner.requests.map(\.arguments), [["uninstall", "--cask", "zed"]])
    }

    func test_full_disk_access_does_not_block_when_data_removal_is_off() {
        let service = makeService(runner: StubBrewProcessRunner())
        service.fullDiskAccessProbe = { .denied }

        XCTAssertFalse(service.zapBlockedByFullDiskAccess)
    }

    func test_uninstall_stays_plain_when_the_caskroom_only_keeps_an_undeclared_helper_app() throws {
        let service = makeService(runner: StubBrewProcessRunner())

        try strandApp(named: "Zed Uninstaller.app")

        XCTAssertEqual(service.uninstallArguments(token: "zed", removingData: false), ["uninstall", "--cask", "zed"])
    }
}
