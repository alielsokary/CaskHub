//
//  TapCategoryDataTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 13/11/2026.
//

@testable import CaskHub
import XCTest

@MainActor
final class TapCategoryDataTests: XCTestCase {
    private let tapJSON = """
    {"version": 1, "generatedDate": "2026-11-13",
     "casks": {"saffsanity/sill/sill": {"primary": "utilities", "secondary": ["design", "made-up"]},
               "user/tap/odd": {"primary": "made-up", "secondary": []}},
     "sameAs": {"ngrok/ngrok/ngrok": "ngrok"},
     "iconCasks": ["saffsanity/sill/sill"]}
    """

    func test_decodes_release_asset() throws {
        let data = try decodeTapData(tapJSON)

        XCTAssertEqual(data.version, 1)
        XCTAssertEqual(data.casks["saffsanity/sill/sill"]?.primary, "utilities")
        XCTAssertEqual(data.sameAs, ["ngrok/ngrok/ngrok": "ngrok"])
        XCTAssertEqual(data.iconCasks, ["saffsanity/sill/sill"])
    }

    func test_mapping_covers_official_tokens_tap_refs_and_aliases() throws {
        let service = try makeService()

        XCTAssertEqual(service.mapping(for: "ngrok"), TokenCategoryMapping(primary: "developer-tools", secondary: []))
        XCTAssertEqual(service.mapping(for: "ngrok/ngrok/ngrok"), service.mapping(for: "ngrok"))
        XCTAssertEqual(service.officialAlias(for: "ngrok/ngrok/ngrok"), "ngrok")
        XCTAssertNil(service.officialAlias(for: "saffsanity/sill/sill"))
        XCTAssertEqual(service.tapIconRefs, ["saffsanity/sill/sill"])
    }

    func test_unknown_category_ids_are_ignored() throws {
        let service = try makeService()

        XCTAssertEqual(service.mapping(for: "saffsanity/sill/sill"), TokenCategoryMapping(primary: "utilities", secondary: ["design"]))
        XCTAssertNil(service.mapping(for: "user/tap/odd"))
        XCTAssertNil(service.mapping(for: "user/tap/unknown"))
    }

    func test_other_versions_are_ignored() throws {
        let service = try makeService()

        service.applyTapData(try decodeTapData(#"{"version": 2, "generatedDate": "", "casks": {}, "sameAs": {}}"#))

        XCTAssertEqual(service.tapIconRefs, ["saffsanity/sill/sill"])
    }

    private func makeService() throws -> CategoryService {
        let official = """
        {"version": 1, "generatedDate": "2026-11-13", "releaseTag": null,
         "categories": {"utilities": {"displayName": "Utilities", "icon": "wrench"},
                        "design": {"displayName": "Design", "icon": "paintbrush"},
                        "developer-tools": {"displayName": "Developer Tools", "icon": "hammer"}},
         "tokenToCategory": {"ngrok": {"primary": "developer-tools", "secondary": []}}}
        """
        let service = CategoryService()
        service.applyData(try JSONDecoder().decode(CaskCategoryData.self, from: Data(official.utf8)))
        service.applyTapData(try decodeTapData(tapJSON))
        return service
    }

    private func decodeTapData(_ json: String) throws -> TapCatalogData {
        try JSONDecoder().decode(TapCatalogData.self, from: Data(json.utf8))
    }
}
