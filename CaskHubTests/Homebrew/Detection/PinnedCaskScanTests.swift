//
//  PinnedCaskScanTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 15/11/2026.
//

@testable import CaskHub
import XCTest

final class PinnedCaskScanTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var caskroom: URL!
    private var pinnedCasks: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fm.temporaryDirectory.appendingPathComponent("pins-\(UUID().uuidString)")
        caskroom = root.appendingPathComponent("Caskroom")
        pinnedCasks = root.appendingPathComponent("var/homebrew/pinned_casks")
        try fm.createDirectory(at: caskroom, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func pin(_ token: String, version: String, createVersionDirectory: Bool = true) throws {
        if createVersionDirectory {
            try fm.createDirectory(
                at: caskroom.appendingPathComponent("\(token)/\(version)"),
                withIntermediateDirectories: true
            )
        }
        try fm.createDirectory(at: pinnedCasks, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: pinnedCasks.appendingPathComponent(token).path,
            withDestinationPath: "../../../Caskroom/\(token)/\(version)"
        )
    }

    private func scanPins() -> [String: String] {
        HomebrewInstallationScanner.scanPinnedCasks(caskroomURL: caskroom, fileManager: fm)
    }

    func test_pin_symlinks_map_token_to_pinned_version() throws {
        try pin("zed", version: "1.2.3")
        try pin("onyx", version: "4.2.1,1234")

        XCTAssertEqual(scanPins(), ["zed": "1.2.3", "onyx": "4.2.1,1234"])
    }

    func test_broken_pin_symlink_is_not_a_pin() throws {
        try pin("gone", version: "9.9", createVersionDirectory: false)

        XCTAssertEqual(scanPins(), [:])
    }

    func test_missing_pinned_casks_directory_means_no_pins() {
        XCTAssertEqual(scanPins(), [:])
    }

    @MainActor
    func test_full_scan_publishes_pins_and_catalog_reconcile_keeps_them() async throws {
        try pin("zed", version: "1.2.3")
        let registration = InstallationCatalogBuilder().build([])
        let request = InstalledSoftwareScanRequest(
            applicationDirectories: [], caskroomURL: caskroom,
            catalog: registration.installationCatalog, applicationSignatures: [], packageSignatures: []
        )
        let scanner = HomebrewInstallationScanner()

        let scanned = await scanner.scan(request)
        XCTAssertEqual(scanned.pinnedVersions, ["zed": "1.2.3"])

        try fm.removeItem(at: pinnedCasks.appendingPathComponent("zed"))
        let reconciled = await scanner.reconcileCatalog(request, with: scanned)
        XCTAssertEqual(reconciled.pinnedVersions, ["zed": "1.2.3"])
    }
}
