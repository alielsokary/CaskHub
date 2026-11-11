//
//  TapAddInputTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/11/2026.
//

@testable import CaskHub
import XCTest

final class TapAddInputTests: XCTestCase {
    func test_tap_name() {
        XCTAssertEqual(parse("hashicorp/tap"), TapAddRequest(tapName: "hashicorp/tap", remoteURL: nil, caskToken: nil))
    }

    func test_github_urls_with_homebrew_prefix_map_to_short_name() {
        let expected = TapAddRequest(tapName: "hashicorp/tap", remoteURL: nil, caskToken: nil)
        XCTAssertEqual(parse("https://github.com/hashicorp/homebrew-tap"), expected)
        XCTAssertEqual(parse("github.com/hashicorp/homebrew-tap.git/"), expected)
    }

    func test_github_url_without_prefix_keeps_explicit_remote() {
        let request = parse("https://github.com/user/casks")
        XCTAssertEqual(request, TapAddRequest(
            tapName: "user/casks", remoteURL: URL(string: "https://github.com/user/casks"), caskToken: nil
        ))
        XCTAssertEqual(request?.brewArguments, ["tap", "user/casks", "https://github.com/user/casks"])
    }

    func test_pasted_install_command_extracts_tap_and_cask() {
        let expected = TapAddRequest(tapName: "saffsanity/sill", remoteURL: nil, caskToken: "sill")
        XCTAssertEqual(parse("brew install --cask saffsanity/sill/sill"), expected)
        XCTAssertEqual(parse("saffsanity/sill/sill"), expected)
        XCTAssertEqual(parse("  brew install --cask saffsanity/sill/sill\n"), expected)
    }

    func test_tap_command_is_lowercased() {
        XCTAssertEqual(parse("brew tap Saffsanity/Sill")?.tapName, "saffsanity/sill")
    }

    func test_empty_and_official_inputs() {
        XCTAssertEqual(TapAddInput.parse("  "), .failure(.empty))
        XCTAssertEqual(TapAddInput.parse("homebrew/cask"), .failure(.officialTap))
    }

    func test_unsafe_or_unknown_input_is_rejected() {
        for text in [
            "brew install --cask foo/bar/baz; rm -rf ~",
            "$(curl x)/a",
            "https://gitlab.com/u/r",
            "fоо/bar",
            "a/b/c/d",
            "-rf/x",
            "foo"
        ] {
            XCTAssertEqual(TapAddInput.parse(text), .failure(.unrecognized), text)
        }
    }

    func test_plain_tap_arguments() {
        XCTAssertEqual(parse("hashicorp/tap")?.brewArguments, ["tap", "hashicorp/tap"])
    }

    private func parse(_ text: String) -> TapAddRequest? {
        try? TapAddInput.parse(text).get()
    }
}
