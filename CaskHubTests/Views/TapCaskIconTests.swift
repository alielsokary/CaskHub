//
//  TapCaskIconTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 12/11/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class TapCaskIconTests: XCTestCase {
    func test_installed_tap_cask_points_at_its_app_in_every_app_folder() {
        let apps = URL(fileURLWithPath: "/tmp/apps-a"), more = URL(fileURLWithPath: "/tmp/apps-b")
        let service = makeService(directories: [apps, more])
        updateInstalledCask(sillInstallation(tap: "saffsanity/sill"), in: service)

        XCTAssertEqual(
            service.installedAppCandidates(for: sill),
            [apps.appendingPathComponent("Sill.app"), more.appendingPathComponent("Sill.app")]
        )
    }

    func test_not_installed_or_twin_installed_has_no_app() {
        let service = makeService(directories: [URL(fileURLWithPath: "/tmp/apps")])
        XCTAssertTrue(service.installedAppCandidates(for: sill).isEmpty)

        updateInstalledCask(sillInstallation(tap: "homebrew/cask"), in: service)
        XCTAssertTrue(service.installedAppCandidates(for: sill).isEmpty, "the official twin's app is not this cask's")
    }

    func test_icon_comes_from_the_first_app_that_exists() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tap-icon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Sill.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let cache = ImageCacheService(diskCache: IconDiskCache(directory: root.appendingPathComponent("cache")))

        let missing = await cache.installedAppIcon(for: sill, candidates: [root.appendingPathComponent("Nope.app")])
        let found = await cache.installedAppIcon(for: sill, candidates: [root.appendingPathComponent("Nope.app"), app])

        XCTAssertNil(missing)
        XCTAssertNotNil(found)
    }

    // MARK: - Helpers

    private let sill = CaskFileTextParser.cask(fromSource: "", token: "sill", tap: "saffsanity/sill")

    private func makeService(directories: [URL]) -> LocalHomebrewService {
        LocalHomebrewService(defaults: makeScratchDefaults("tap-icon-\(UUID().uuidString)")) {
            $0.softwareScanner = MutableInstalledSoftwareScanner()
            $0.applicationDirectories = directories
        }
    }

    private func sillInstallation(tap: String) -> LocalCaskInstallation {
        LocalCaskInstallation(token: "sill", installedVersion: "0.6.1", installedAt: nil, appBundleNames: ["Sill.app"], tap: tap)
    }
}
