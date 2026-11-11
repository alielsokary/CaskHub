//
//  CaskFileTextParserTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/11/2026.
//

@testable import CaskHub
import XCTest

final class CaskFileTextParserTests: XCTestCase {
    func test_simple_cask() {
        let source = """
        cask "halloy" do
          version "2026.10"

          url "https://github.com/squidowl/halloy/releases/download/2026.10/halloy.dmg"
          name "halloy"
          desc "IRC application written in Rust"
          homepage "https://github.com/squidowl/halloy"
          sha256 "3817b63334698599ae472fd9790f0594ef5cfae68124d5775ab8025f2aab4273"

          auto_updates true

          app "halloy.app"

          zap trash: [
            "~/Library/Application Support/halloy",
          ]
        end
        """

        let cask = CaskFileTextParser.cask(fromSource: source, token: "halloy", tap: "romankurnovskii/awesome-brew")

        XCTAssertEqual(cask.displayName, "halloy")
        XCTAssertEqual(cask.desc, "IRC application written in Rust")
        XCTAssertEqual(cask.version, "2026.10")
        XCTAssertEqual(cask.homepage, "https://github.com/squidowl/halloy")
        XCTAssertEqual(cask.reference, "romankurnovskii/awesome-brew/halloy")
        XCTAssertEqual(cask.provenance, .tapSource)
    }

    func test_arch_blocks_take_first_version() {
        let source = """
        cask "tool" do
          on_arm do
            version "2.0"
          end
          on_intel do
            version "1.9"
          end
          name "Tool"
        end
        """

        XCTAssertEqual(CaskFileTextParser.cask(fromSource: source, token: "tool", tap: "u/r").version, "2.0")
    }

    func test_interpolated_desc_is_dropped() {
        let source = """
        cask "tool" do
          version "1.0"
          desc "#{name} app"
        end
        """

        XCTAssertNil(CaskFileTextParser.cask(fromSource: source, token: "tool", tap: "u/r").desc)
    }

    func test_v_prefixed_version_is_shown_once() {
        let source = "cask \"tool\" do\n  version \"v0.27.4\"\nend\n"
        let cask = CaskFileTextParser.cask(fromSource: source, token: "tool", tap: "u/r")

        XCTAssertEqual(cask.displayVersion, "0.27.4")
        XCTAssertEqual(cask.metaLine(downloads: nil), "v0.27.4")
    }

    func test_latest_version() {
        let source = """
        cask "tool" do
          version :latest
        end
        """

        XCTAssertEqual(CaskFileTextParser.cask(fromSource: source, token: "tool", tap: "u/r").version, "latest")
    }

    func test_non_web_homepage_is_dropped() {
        for homepage in ["file:///etc/passwd", "javascript:alert(1)", "x-apple.systempreferences:", "https://"] {
            let source = "cask \"tool\" do\n  homepage \"\(homepage)\"\nend\n"
            XCTAssertEqual(CaskFileTextParser.cask(fromSource: source, token: "tool", tap: "u/r").homepage, "", homepage)
        }
    }

    func test_garbage_source() {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0 ..< 200_000).map { _ in UInt8.random(in: 0 ... 255, using: &generator) }
        let source = String(bytes: bytes, encoding: .isoLatin1) ?? ""
        let start = Date()

        let cask = CaskFileTextParser.cask(fromSource: source, token: "junk", tap: "u/r")

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1)
        XCTAssertEqual(cask.displayName, "junk")
        XCTAssertEqual(cask.version, "")
        XCTAssertEqual(cask.homepage, "")
    }
}
