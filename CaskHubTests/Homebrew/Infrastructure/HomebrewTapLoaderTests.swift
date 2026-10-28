//
//  HomebrewTapLoaderTests.swift
//  CaskHubTests
//

@testable import CaskHub
import XCTest

final class HomebrewTapLoaderTests: XCTestCase {
    func test_tap_names_skip_the_official_taps_and_blank_lines() {
        XCTAssertEqual(
            HomebrewTapLoader.tapNames(in: "homebrew/core\nhomebrew/cask\n\nacme/apps\n  extra/tap \n"),
            ["acme/apps", "extra/tap"]
        )
    }

    func test_taps_parse_cask_tokens_and_reject_garbage() throws {
        let output = """
        [{"name":"acme/apps","cask_tokens":["acme/apps/widget"],"formula_names":[]},
         {"name":"zeta/tap","formula_names":["zeta/tap/tool"]},
         {"name":"homebrew/core","cask_tokens":[]}]
        """
        XCTAssertEqual(HomebrewTapLoader.taps(in: output), [
            HomebrewTap(name: "acme/apps", caskTokens: ["acme/apps/widget"]),
            HomebrewTap(name: "zeta/tap", caskTokens: [])
        ])
        XCTAssertNil(HomebrewTapLoader.taps(in: "Error: no tap"))
    }

    func test_cask_info_decodes_each_cask_and_skips_the_ones_it_cannot_read() {
        let output = """
        {"formulae":[],"casks":[
          {"token":"widget","full_token":"acme/apps/widget","tap":"acme/apps","name":["Widget"],
           "desc":"Git client","homepage":"https://example.com","version":"0.2.1","auto_updates":false,
           "outdated":false,"deprecated":false,"disabled":false,"installed":"0.2.1",
           "artifacts":[{"app":["Widget.app"]},{"zap":[{"trash":["~/x"]}]}]},
          {"token":"broken"}
        ]}
        """
        let casks = HomebrewTapLoader.casks(in: output)
        XCTAssertEqual(casks.map(\.token), ["widget"])
        XCTAssertEqual(casks.first?.brewToken, "acme/apps/widget")
        XCTAssertEqual(casks.first?.appArtifactNames, ["Widget.app"])
        XCTAssertEqual(casks.first?.metaLine(downloads: nil), "v0.2.1 · acme/apps")
        XCTAssertTrue(HomebrewTapLoader.casks(in: "Error").isEmpty)
    }

    func test_tap_names_are_normalized_and_unsafe_input_is_rejected() {
        XCTAssertEqual(HomebrewTapName.normalized("Acme/apps"), "acme/apps")
        XCTAssertEqual(HomebrewTapName.normalized(" acme/homebrew-apps "), "acme/apps")
        XCTAssertEqual(HomebrewTapName.normalized("https://github.com/acme/homebrew-apps.git"), "acme/apps")
        XCTAssertNil(HomebrewTapName.normalized("acme"))
        XCTAssertNil(HomebrewTapName.normalized("--force/apps"))
        XCTAssertNil(HomebrewTapName.normalized("a/b/c"))
        XCTAssertNil(HomebrewTapName.normalized("a/b c"))
        XCTAssertTrue(HomebrewTapName.isValidRemote("https://example.com/tap.git"))
        XCTAssertTrue(HomebrewTapName.isValidRemote("git@example.com:me/tap.git"))
        XCTAssertFalse(HomebrewTapName.isValidRemote("--config=evil"))
        XCTAssertFalse(HomebrewTapName.isValidRemote("https://a b"))
    }

    func test_add_rejects_an_invalid_name_without_running_brew() async {
        let result = await HomebrewTapLoader().add("not a tap", remote: nil, using: URL(fileURLWithPath: "/nonexistent/brew"))
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.output.isEmpty)
    }

    func test_brewfile_export_declares_the_taps_of_qualified_casks() {
        XCTAssertEqual(
            Brewfile.contents(forCaskTokens: ["zed", "acme/apps/gadget", "acme/apps/widget"]),
            "tap \"acme/apps\"\ncask \"acme/apps/gadget\"\ncask \"acme/apps/widget\"\ncask \"zed\"\n"
        )
    }
}
