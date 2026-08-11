//
//  CaskMetadataProjectorTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 29/07/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class CaskMetadataProjectorTests: XCTestCase {
    func test_category_projection_resolves_main_and_subcategory_names() {
        let mappings = [
            "studio": TokenCategoryMapping(
                primary: "developer-tools",
                secondary: ["productivity", "utilities"]
            )
        ]
        let definitions = [
            "developer-tools": CategoryDefinition(
                displayName: "Developer Tools",
                icon: "hammer"
            ),
            "productivity": CategoryDefinition(
                displayName: "Productivity",
                icon: "checklist"
            ),
            "utilities": CategoryDefinition(
                displayName: "Utilities",
                icon: "wrench"
            )
        ]

        XCTAssertEqual(
            CaskCategoryProjector.make(
                token: "studio",
                mappings: mappings,
                definitions: definitions
            ),
            CaskCategoryPresentation(
                mainID: "developer-tools",
                mainName: "Developer Tools",
                subcategoryNames: ["Productivity", "Utilities"]
            )
        )
        XCTAssertNil(CaskCategoryProjector.make(
            token: "unknown",
            mappings: mappings,
            definitions: definitions
        ))
    }

    func test_info_projection_shows_homebrew_dates_and_catalog_metadata() {
        let installedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let lastUpdatedAt = Date(timeIntervalSince1970: 1_710_000_000)
        let rows = makeRows(
            source: .homebrew,
            dates: CaskInstallationDates(
                installedAt: installedAt,
                lastUpdatedAt: lastUpdatedAt,
                basis: .homebrewMetadata
            )
        )
        let values = valuesByProperty(rows)

        let no = String(localized: "No")
        XCTAssertEqual(values[String(localized: "Main Category")], "Developer Tools")
        XCTAssertEqual(values[String(localized: "Subcategories")], "Productivity, Utilities")
        XCTAssertEqual(
            values[String(localized: .caskDateLabelInstalled)],
            installedAt.formatted(date: .abbreviated, time: .shortened)
        )
        XCTAssertEqual(
            values[String(localized: "Last Updated")],
            lastUpdatedAt.formatted(date: .abbreviated, time: .shortened)
        )
        XCTAssertEqual(values[String(localized: "Outdated")], no)
        XCTAssertEqual(values[String(localized: "Deprecated")], no)
        XCTAssertEqual(values[String(localized: "Disabled")], no)
        XCTAssertEqual(
            rows.suffix(3).map(\.property),
            [
                String(localized: "Outdated"),
                String(localized: "Deprecated"),
                String(localized: "Disabled")
            ]
        )
    }

    func test_info_projection_labels_bundle_file_dates_as_best_effort_metadata() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let modifiedAt = Date(timeIntervalSince1970: 1_710_000_000)
        let values = valuesByProperty(makeRows(
            source: .externalApplication,
            dates: CaskInstallationDates(
                installedAt: createdAt,
                lastUpdatedAt: modifiedAt,
                basis: .applicationBundleAttributes
            )
        ))

        XCTAssertEqual(
            values[String(localized: "Bundle Created")],
            createdAt.formatted(date: .abbreviated, time: .shortened)
        )
        XCTAssertEqual(
            values[String(localized: "Bundle Modified")],
            modifiedAt.formatted(date: .abbreviated, time: .shortened)
        )
        XCTAssertNil(values[String(localized: .caskDateLabelInstalled)])
        XCTAssertNil(values[String(localized: "Last Updated")])
    }

    func test_info_projection_shows_sha256_row_after_url() {
        let hex = String(repeating: "ab", count: 32)
        let rows = makeDownloadRows(sha256: hex)

        XCTAssertEqual(valuesByProperty(rows)["SHA"], hex)
        XCTAssertEqual(
            rows.map(\.property).filter { ["URL", "SHA"].contains($0) },
            ["URL", "SHA"]
        )
    }

    func test_info_projection_softens_no_check_sha256() {
        XCTAssertEqual(
            valuesByProperty(makeDownloadRows(sha256: "no_check"))["SHA"],
            String(localized: "sha256 :no_check (rolling download URL)")
        )
    }

    func test_info_projection_omits_sha256_row_when_missing() {
        XCTAssertNil(valuesByProperty(makeDownloadRows(sha256: nil))["SHA"])
    }

    private func makeDownloadRows(sha256: String?) -> [CaskInfoRow] {
        CaskInfoProjector.makeRows(from: CaskInfoProjectionInput(
            cask: Cask.preview(
                token: "studio",
                url: "https://example.com/studio.dmg",
                sha256: sha256
            ),
            category: nil,
            downloadSize: .unknown,
            actionPresentation: CaskActionPresentation(
                localState: CaskLocalState(
                    installationSource: nil,
                    externalVersion: nil,
                    adoptionPlan: nil,
                    externalCLIPath: nil,
                    uninstallAvailability: .unavailable(reason: "Not installed"),
                    hasAvailableUpdate: false,
                    isZombie: false,
                    canOpen: false
                ),
                homebrewInstallation: nil,
                operationState: nil
            ),
            externalVersion: nil,
            installationDates: nil
        ))
    }

    private func makeRows(
        source: CaskInstallationSource,
        dates: CaskInstallationDates
    ) -> [CaskInfoRow] {
        let cask = makeCask("studio")
        let installation = source == .homebrew
            ? LocalCaskInstallation(
                token: cask.token,
                installedVersion: "3.1",
                installedAt: dates.installedAt,
                lastUpdatedAt: dates.lastUpdatedAt,
                appBundleNames: []
            )
            : nil
        let externalVersion = source == .homebrew ? nil : "3.1"
        let localState = CaskLocalState(
            installationSource: source,
            externalVersion: externalVersion,
            adoptionPlan: CaskAdoptionPlan.make(
                installationSource: source,
                installedVersion: externalVersion,
                homebrewVersion: cask.displayVersion,
                installedCaskTokens: [],
                conflictingCaskTokens: []
            ),
            externalCLIPath: nil,
            uninstallAvailability: source == .homebrew
                ? .available
                : .unavailable(reason: "Managed elsewhere"),
            hasAvailableUpdate: false,
            isZombie: false,
            canOpen: true
        )
        return CaskInfoProjector.makeRows(from: CaskInfoProjectionInput(
            cask: cask,
            category: CaskCategoryPresentation(
                mainID: "developer-tools",
                mainName: "Developer Tools",
                subcategoryNames: ["Productivity", "Utilities"]
            ),
            downloadSize: .unknown,
            actionPresentation: CaskActionPresentation(
                localState: localState,
                homebrewInstallation: installation,
                operationState: nil
            ),
            externalVersion: externalVersion,
            installationDates: dates
        ))
    }

    private func valuesByProperty(_ rows: [CaskInfoRow]) -> [String: String] {
        Dictionary(
            rows.map { ($0.property, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
