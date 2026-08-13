//
//  CaskAdoptionPlanTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 10/08/2026.
//

@testable import CaskHub
import XCTest

final class CaskAdoptionPlanTests: XCTestCase {
    private struct Fixture {
        let source: CaskInstallationSource
        let installedVersion: String?
        let relationship: CaskAdoptionVersionRelationship
        let operation: CaskAdoptionOperation
        let execution: CaskAdoptionExecution
    }

    private var fixtures: [Fixture] {
        [
            Fixture(
                source: .externalApplication, installedVersion: "2.0",
                relationship: .homebrewOlder, operation: .downgradeAndAdopt,
                execution: .replaceApplication
            ),
            Fixture(
                source: .externalApplication, installedVersion: "0.9",
                relationship: .homebrewNewer, operation: .updateAndAdopt,
                execution: .replaceApplication
            ),
            Fixture(
                source: .externalApplication, installedVersion: "1.0",
                relationship: .same, operation: .adopt,
                execution: .adoptApplication
            ),
            Fixture(
                source: .packageInstaller, installedVersion: "2.0",
                relationship: .homebrewOlder, operation: .downgradeAndAdopt,
                execution: .replacePackage
            ),
            Fixture(
                source: .packageInstaller, installedVersion: "0.9",
                relationship: .homebrewNewer, operation: .updateAndAdopt,
                execution: .installPackage
            ),
            Fixture(
                source: .packageInstaller, installedVersion: "1.0",
                relationship: .same, operation: .adopt,
                execution: .replacePackage
            ),
            Fixture(
                source: .packageInstaller, installedVersion: nil,
                relationship: .unknown, operation: .adopt,
                execution: .installPackage
            )
        ]
    }

    func test_numeric_version_comparison_handles_onedrive_and_uncertain_versions() {
        XCTAssertEqual(
            NumericVersionComparison.compare("26.129.0706", "26.119.0622.0003"),
            .orderedDescending
        )
        XCTAssertEqual(NumericVersionComparison.compare("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(NumericVersionComparison.compare("1.2.0", "1.2.1"), .orderedAscending)
        XCTAssertNil(NumericVersionComparison.compare("latest", "1.0"))
    }

    func test_planner_maps_artifact_and_version_to_one_operation() throws {
        for fixture in fixtures {
            let plan = try XCTUnwrap(CaskAdoptionPlan.make(
                installationSource: fixture.source,
                installedVersion: fixture.installedVersion,
                homebrewVersion: "1.0",
                installedCaskTokens: [],
                conflictingCaskTokens: []
            ))
            XCTAssertEqual(plan.versionRelationship, fixture.relationship)
            XCTAssertEqual(plan.operation, fixture.operation)
            XCTAssertEqual(plan.execution, fixture.execution)
        }
    }

    func test_planner_blocks_an_installed_conflicting_cask() throws {
        let plan = try XCTUnwrap(CaskAdoptionPlan.make(
            installationSource: .packageInstaller,
            installedVersion: "1.0",
            homebrewVersion: "1.0",
            installedCaskTokens: ["microsoft-excel"],
            conflictingCaskTokens: ["microsoft-word", "microsoft-excel"]
        ))

        XCTAssertEqual(plan.blockingInstalledCask, "microsoft-excel")
    }
}
