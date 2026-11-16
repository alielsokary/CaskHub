//
//  CaskReferenceTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/11/2026.
//

@testable import CaskHub
import XCTest

final class CaskReferenceTests: XCTestCase {
    func test_make_keeps_official_tokens_bare_and_qualifies_tap_tokens() {
        XCTAssertEqual(CaskReference.make(token: "foo", tap: "homebrew/cask"), "foo")
        XCTAssertEqual(CaskReference.make(token: "foo", tap: nil), "foo")
        XCTAssertEqual(CaskReference.make(token: "sill", tap: "saffsanity/sill"), "saffsanity/sill/sill")
    }

    func test_bare_token_and_tap_split_a_reference() {
        XCTAssertEqual(CaskReference.bareToken("saffsanity/sill/sill"), "sill")
        XCTAssertEqual(CaskReference.bareToken("figma"), "figma")
        XCTAssertEqual(CaskReference.tap(of: "saffsanity/sill/sill"), "saffsanity/sill")
        XCTAssertNil(CaskReference.tap(of: "foo"))
    }

    func test_normalized_drops_official_tap_prefix_only() {
        XCTAssertEqual(CaskReference.normalized("homebrew/cask-versions/firefox-beta"), "firefox-beta")
        XCTAssertEqual(CaskReference.normalized("saffsanity/sill/sill"), "saffsanity/sill/sill")
        XCTAssertEqual(CaskReference.normalized("figma"), "figma")
    }

    func test_analytics_name_hides_tap_casks_and_tap_operations() {
        XCTAssertEqual(CaskReference.analyticsName("my-monkeys/tap/opensuperwhisper"), "third-party")
        XCTAssertEqual(CaskReference.analyticsName("caskhub-tap:saffsanity/sill"), "third-party")
        XCTAssertEqual(CaskReference.analyticsName("figma"), "figma")
    }

    func test_official_tap_check_ignores_case() {
        XCTAssertTrue(CaskReference.isOfficial(tap: "Homebrew/Cask"))
        XCTAssertEqual(CaskReference.normalized("Homebrew/Cask/foo"), "foo")
    }

    func test_snapshot_lookup_requires_matching_tap() {
        let snapshot = InstallationSnapshot(installedCasks: [
            "opensuperwhisper": installation("opensuperwhisper", tap: "my-monkeys/tap")
        ])

        XCTAssertNil(snapshot.installation(for: "opensuperwhisper"))
        XCTAssertNotNil(snapshot.installation(for: "my-monkeys/tap/opensuperwhisper"))
        XCTAssertEqual(snapshot.foreignInstallationSource(for: "opensuperwhisper"), "my-monkeys/tap")
        XCTAssertNil(snapshot.foreignInstallationSource(for: "my-monkeys/tap/opensuperwhisper"))
    }

    func test_official_install_is_foreign_to_tap_twin() {
        let snapshot = InstallationSnapshot(installedCasks: [
            "foo": installation("foo", tap: "homebrew/cask")
        ])

        XCTAssertEqual(snapshot.foreignInstallationSource(for: "user/tap/foo"), "Homebrew")
        XCTAssertNil(snapshot.installation(for: "user/tap/foo"))
    }

    func test_receipt_without_tap_counts_as_official() {
        let snapshot = InstallationSnapshot(installedCasks: ["foo": installation("foo", tap: nil)])

        XCTAssertNotNil(snapshot.installation(for: "foo"))
        XCTAssertNil(snapshot.foreignInstallationSource(for: "foo"))
    }

    func test_official_api_cask_id_is_its_token() throws {
        let json = """
        {"token": "figma", "full_token": "figma", "tap": "homebrew/cask", "name": ["Figma"],
         "homepage": "https://figma.com", "version": "1.0",
         "outdated": false, "deprecated": false, "disabled": false}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let cask = try decoder.decode(Cask.self, from: Data(json.utf8))

        XCTAssertEqual(cask.reference, "figma")
        XCTAssertEqual(cask.id, "figma")
    }

    func test_tap_receipt_row_id_is_qualified() {
        let row = Cask.receiptRow(for: installation("sill", tap: "saffsanity/sill"))

        XCTAssertEqual(row.id, "saffsanity/sill/sill")
    }

    func test_receipt_rows_from_any_official_tap_read_as_removed_from_homebrew() {
        for tap in ["homebrew/cask", "homebrew/cask-fonts", "Homebrew/cask-versions", nil] {
            let row = Cask.receiptRow(for: installation("gone", tap: tap))
            XCTAssertEqual(row.retirement(for: nil), .removedFromHomebrew, tap ?? "nil")
        }
        XCTAssertNil(Cask.receiptRow(for: installation("sill", tap: "saffsanity/sill")).retirement(for: nil))
    }

    private func installation(_ token: String, tap: String?) -> LocalCaskInstallation {
        LocalCaskInstallation(
            token: token,
            installedVersion: "1.0",
            installedAt: nil,
            appBundleNames: [],
            tap: tap
        )
    }
}
