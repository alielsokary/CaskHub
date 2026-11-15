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
            "fоо/bar",
            "a/b/c/d",
            "-rf/x",
            "foo"
        ] {
            XCTAssertEqual(TapAddInput.parse(text), .failure(.unrecognized), text)
        }
    }

    func test_https_urls_on_other_hosts_keep_their_remote() {
        XCTAssertEqual(parse("https://gitlab.com/group/homebrew-tools"), TapAddRequest(
            tapName: "group/tools", remoteURL: URL(string: "https://gitlab.com/group/homebrew-tools"), caskToken: nil
        ))
        let codeberg = parse("https://codeberg.org/User/Casks.git/")
        XCTAssertEqual(codeberg, TapAddRequest(
            tapName: "user/casks", remoteURL: URL(string: "https://codeberg.org/User/Casks.git"), caskToken: nil
        ))
        XCTAssertEqual(codeberg?.brewArguments, ["tap", "user/casks", "https://codeberg.org/User/Casks.git"])
        XCTAssertEqual(parse("https://git.example.com:8443/org/homebrew-apps")?.remoteURL,
                       URL(string: "https://git.example.com:8443/org/homebrew-apps"))
    }

    func test_unencrypted_remotes_are_refused() {
        XCTAssertEqual(TapAddInput.parse("http://gitlab.com/u/homebrew-r"), .failure(.insecureRemote))
        XCTAssertEqual(TapAddInput.parse("git://example.com/u/homebrew-r"), .failure(.insecureRemote))
    }

    func test_other_remote_forms_are_not_recognized() {
        for text in [
            "https://user:token@gitlab.com/u/homebrew-r",
            "https://gitlab.com/u/homebrew-r?ref=main",
            "https://gitlab.com/u/homebrew-r/-/tree/main",
            "https://github.com/u/homebrew-r/tree/main",
            "https://git.example.com/org/sub/homebrew-apps",
            "https://gitlab.com/u/..",
            "https://gitlab.com/u",
            "git@gitlab.com:u/homebrew-r.git",
            "ssh://git@gitlab.com/u/homebrew-r",
            "file:///tmp/homebrew-r"
        ] {
            XCTAssertEqual(TapAddInput.parse(text), .failure(.unrecognized), text)
        }
    }

    func test_plain_tap_arguments() {
        XCTAssertEqual(parse("hashicorp/tap")?.brewArguments, ["tap", "hashicorp/tap"])
    }

    func test_install_command_rewrites_to_tap_command() throws {
        let rewrite = try XCTUnwrap(TapAddInput.tapCommandRewrite(for: "brew install --cask saffsanity/sill/sill"))

        XCTAssertEqual(rewrite.keptPrefix, "brew")
        XCTAssertEqual(rewrite.removedWords, "install --cask")
        XCTAssertEqual(rewrite.addedWords, "tap")
        XCTAssertEqual(rewrite.tapName, "saffsanity/sill")
        XCTAssertEqual(rewrite.removedSuffix, "/sill")
        XCTAssertEqual(rewrite.finalText, "brew tap saffsanity/sill")
        XCTAssertEqual(rewrite.caskToken, "sill")
    }

    func test_qualified_token_rewrites_with_brew_tap_added() throws {
        let rewrite = try XCTUnwrap(TapAddInput.tapCommandRewrite(for: "saffsanity/sill/sill"))

        XCTAssertEqual(rewrite.keptPrefix, "")
        XCTAssertEqual(rewrite.removedWords, "")
        XCTAssertEqual(rewrite.addedWords, "brew tap")
        XCTAssertEqual(rewrite.finalText, "brew tap saffsanity/sill")
    }

    func test_inputs_without_a_cask_are_not_rewritten() {
        XCTAssertNil(TapAddInput.tapCommandRewrite(for: "hashicorp/tap"))
        XCTAssertNil(TapAddInput.tapCommandRewrite(for: "brew tap hashicorp/tap"))
        XCTAssertNil(TapAddInput.tapCommandRewrite(for: "foo; rm -rf ~"))
    }

    private func parse(_ text: String) -> TapAddRequest? {
        try? TapAddInput.parse(text).get()
    }
}
