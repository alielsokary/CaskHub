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
            Brewfile.contents(forCaskTokens: ["raycast", "figma"]),
            "cask \"figma\"\ncask \"raycast\"\n"
        )
        XCTAssertEqual(Brewfile.contents(forCaskTokens: []), "")
    }

    func test_roundtrip_preserves_tokens() {
        let tokens = ["figma", "google-chrome", "raycast"]
        XCTAssertEqual(
            Brewfile.caskTokens(in: Brewfile.contents(forCaskTokens: tokens)),
            tokens
        )
    }
}
