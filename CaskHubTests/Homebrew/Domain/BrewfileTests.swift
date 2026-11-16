//
//  BrewfileTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 15/08/2026.
//

@testable import CaskHub
import XCTest

final class BrewfileTests: XCTestCase {
    func test_parsing_extracts_only_cask_entries() {
        let contents = """
        # my machine
        tap "mongodb/brew"
        brew "wget"
        cask "google-chrome"
          cask 'figma'
        cask "raycast", args: { appdir: "~/Applications" }
        mas "Keynote", id: 409183694
        casket "not-a-cask"
        """
        XCTAssertEqual(
            Brewfile.caskTokens(in: contents),
            ["google-chrome", "figma", "raycast"]
        )
    }

    func test_parsing_keeps_tap_qualified_tokens_and_dedupes() {
        let contents = """
        cask "homebrew/cask-versions/firefox-beta"
        cask "figma"
        cask "figma"
        """
        XCTAssertEqual(
            Brewfile.caskTokens(in: contents),
            ["homebrew/cask-versions/firefox-beta", "figma"]
        )
    }

    func test_parsing_empty_or_caskless_contents_returns_nothing() {
        XCTAssertEqual(Brewfile.caskTokens(in: ""), [])
        XCTAssertEqual(Brewfile.caskTokens(in: "brew \"wget\"\n# cask \"x\" y"), [])
    }

    func test_serializing_sorts_tokens_into_cask_lines() {
        XCTAssertEqual(
            Brewfile.contents(forCaskReferences: ["raycast", "figma"]),
            "cask \"figma\"\ncask \"raycast\"\n"
        )
        XCTAssertEqual(Brewfile.contents(forCaskReferences: []), "")
    }

    func test_roundtrip_preserves_tokens() {
        let tokens = ["figma", "google-chrome", "raycast"]
        XCTAssertEqual(
            Brewfile.caskTokens(in: Brewfile.contents(forCaskReferences: tokens)),
            tokens
        )
    }

    func test_parsing_taps_keeps_urls_skips_official_and_dedupes() {
        let contents = """
        tap "hashicorp/tap"
        tap 'user/casks', "https://github.com/user/casks"
        tap "homebrew/cask"
        tap "hashicorp/tap"
        cask "figma"
        """

        XCTAssertEqual(Brewfile.taps(in: contents), BrewfileTaps(toAdd: [
            TapAddRequest(tapName: "hashicorp/tap", remoteURL: nil, caskToken: nil),
            TapAddRequest(tapName: "user/casks", remoteURL: URL(string: "https://github.com/user/casks"), caskToken: nil)
        ]))
    }

    func test_tap_with_an_unusable_remote_is_never_added_from_its_name_alone() {
        let contents = """
        tap "user/ssh", "git@gitlab.com:user/homebrew-ssh.git"
        tap "user/plain", "http://example.com/user/homebrew-plain"
        tap "user/creds", "https://token@example.com/user/homebrew-creds"
        tap "user/ok", "https://gitlab.com/user/homebrew-ok"
        """

        XCTAssertEqual(Brewfile.taps(in: contents), BrewfileTaps(
            toAdd: [TapAddRequest(tapName: "user/ok", remoteURL: URL(string: "https://gitlab.com/user/homebrew-ok"), caskToken: nil)],
            unsupported: ["user/ssh", "user/plain", "user/creds"]
        ))
    }

    func test_export_writes_taps_before_qualified_casks() {
        XCTAssertEqual(
            Brewfile.contents(forCaskReferences: ["saffsanity/sill/sill", "figma"]),
            "tap \"saffsanity/sill\"\ncask \"figma\"\ncask \"saffsanity/sill/sill\"\n"
        )
    }
}
