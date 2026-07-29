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

        XCTAssertEqual(values["Main Category"], "Developer Tools")
        XCTAssertEqual(values["Subcategories"], "Productivity, Utilities")
        XCTAssertEqual(
            values["Installed"],
            installedAt.formatted(date: .abbreviated, time: .shortened)
        )
        XCTAssertEqual(
            values["Last Updated"],
            lastUpdatedAt.formatted(date: .abbreviated, time: .shortened)
        )
        XCTAssertNil(values["Outdated"])
        XCTAssertNil(values["Deprecated"])
        XCTAssertNil(values["Disabled"])
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
            values["Bundle Created"],
            createdAt.formatted(date: .abbreviated, time: .shortened)
        )
        XCTAssertEqual(
            values["Bundle Modified"],
            modifiedAt.formatted(date: .abbreviated, time: .shortened)
        )
        XCTAssertNil(values["Installed"])
        XCTAssertNil(values["Last Updated"])
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
        let localState = CaskLocalState(
            installationSource: source,
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
            externalVersion: source == .homebrew ? nil : "3.1",
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
