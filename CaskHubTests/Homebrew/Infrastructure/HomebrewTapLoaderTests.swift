//
//  HomebrewTapLoaderTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 11/11/2026.
//

@testable import CaskHub
import XCTest

final class HomebrewTapLoaderTests: XCTestCase {
    private let tapInfoJSON = """
    [{"name": "homebrew/cask", "path": "/opt/homebrew/Library/Taps/homebrew/homebrew-cask", "official": true,
      "trusted": true, "formula_names": [], "cask_tokens": ["figma"]},
     {"name": "macos-fuse-t/cask", "path": "/opt/homebrew/Library/Taps/macos-fuse-t/homebrew-cask",
      "official": false, "trusted": false, "formula_names": ["macos-fuse-t/cask/sshfs-fuse-t"],
      "cask_tokens": ["macos-fuse-t/cask/fuse-t-sshfs", "macos-fuse-t/cask/fuse-t"],
      "cask_files": ["/opt/homebrew/Library/Taps/macos-fuse-t/homebrew-cask/Casks/fuse-t-sshfs.rb",
                     "/opt/homebrew/Library/Taps/macos-fuse-t/homebrew-cask/Casks/f/fuse-t.rb"],
      "remote": "https://github.com/macos-fuse-t/homebrew-cask"},
     {"name": "paninihouse/brewer-cmd", "path": "/opt/homebrew/Library/Taps/paninihouse/homebrew-brewer-cmd",
      "official": false, "trusted": true, "formula_names": [], "cask_tokens": [], "cask_files": [],
      "remote": "https://github.com/paninihouse/homebrew-brewer-cmd"}]
    """

    private let trustJSON = """
    {"taps": ["paninihouse/brewer-cmd"], "formulae": ["cameroncooke/axe/axe"],
     "casks": ["macos-fuse-t/cask/fuse-t"], "commands": []}
    """

    func test_tap_info_decoding_drops_official_taps_and_counts_items() throws {
        let taps = try XCTUnwrap(HomebrewTapLoader.taps(in: tapInfoJSON))

        XCTAssertEqual(taps.map(\.name), ["macos-fuse-t/cask", "paninihouse/brewer-cmd"])
        XCTAssertEqual(taps[0].caskCount, 2)
        XCTAssertEqual(taps[0].formulaCount, 1)
        XCTAssertFalse(taps[0].trusted)
        XCTAssertEqual(taps[0].remote, "https://github.com/macos-fuse-t/homebrew-cask")
    }

    func test_trust_covers_casks_whole_taps_and_official_casks() throws {
        let trust = try XCTUnwrap(HomebrewTapLoader.trust(in: trustJSON))

        XCTAssertTrue(trust.trusts("macos-fuse-t/cask/fuse-t"))
        XCTAssertTrue(trust.trusts("paninihouse/brewer-cmd/anything"))
        XCTAssertFalse(trust.trusts("macos-fuse-t/cask/fuse-t-sshfs"))
        XCTAssertFalse(trust.trusts("romankurnovskii/awesome-brew/halloy"))
        XCTAssertTrue(trust.trusts("figma"))
    }

    func test_garbage_output_is_rejected() {
        XCTAssertNil(HomebrewTapLoader.taps(in: "garbage"))
        XCTAssertNil(HomebrewTapLoader.trust(in: "Error: oops"))
    }

    func test_index_uses_brew_json_for_trusted_and_text_for_untrusted_casks() throws {
        let taps = try XCTUnwrap(HomebrewTapLoader.taps(in: tapInfoJSON))
        let trust = try XCTUnwrap(HomebrewTapLoader.trust(in: trustJSON))
        let trustedInfo = [try tapInfoCask("fuse-t", tap: "macos-fuse-t/cask", version: "1.2.9")]
        var readPaths: [String] = []

        let index = HomebrewTapLoader.makeIndex(taps: taps, trust: trust, trustedCasks: trustedInfo) { path in
            readPaths.append(path)
            return "cask \"fuse-t-sshfs\" do\n  version \"1.0.2\"\n  name \"SSHFS\"\nend\n"
        }

        XCTAssertEqual(index.casks.map(\.reference), ["macos-fuse-t/cask/fuse-t", "macos-fuse-t/cask/fuse-t-sshfs"])
        XCTAssertEqual(index.casks.map(\.provenance), [.tapInfo, .tapSource])
        XCTAssertEqual(index.casks[1].displayName, "SSHFS")
        XCTAssertEqual(readPaths, ["/opt/homebrew/Library/Taps/macos-fuse-t/homebrew-cask/Casks/fuse-t-sshfs.rb"])
        XCTAssertEqual(index.casks(in: "macos-fuse-t/cask").count, 2)
        XCTAssertTrue(index.casks(in: "paninihouse/brewer-cmd").isEmpty)
    }

    func test_trusted_cask_missing_from_brew_json_falls_back_to_text() throws {
        let taps = try XCTUnwrap(HomebrewTapLoader.taps(in: tapInfoJSON))
        let trust = try XCTUnwrap(HomebrewTapLoader.trust(in: trustJSON))

        let index = HomebrewTapLoader.makeIndex(taps: taps, trust: trust, trustedCasks: nil) { _ in
            "cask \"x\" do\n  version \"9\"\nend\n"
        }

        XCTAssertEqual(index.casks.map(\.provenance), [.tapSource, .tapSource])
    }

    func test_unreadable_cask_file_still_lists_the_token() throws {
        let taps = try XCTUnwrap(HomebrewTapLoader.taps(in: tapInfoJSON))
        let trust = TapTrust(taps: [], casks: [])

        let index = HomebrewTapLoader.makeIndex(taps: taps, trust: trust, trustedCasks: nil) { _ in nil }

        XCTAssertEqual(index.casks.map(\.displayName), ["fuse-t", "fuse-t-sshfs"])
    }

    func test_custom_remote_taps_match_trust_by_remote_url() throws {
        let json = """
        [{"name": "user/casks", "official": false, "trusted": false, "custom_remote": true,
          "remote": "https://GitHub.com/User/casks", "cask_tokens": ["user/casks/tool"], "cask_files": []},
         {"name": "user/whole", "official": false, "trusted": true, "custom_remote": false,
          "remote": "https://github.com/user/homebrew-whole", "cask_tokens": ["user/whole/app"], "cask_files": []}]
        """
        let taps = try XCTUnwrap(HomebrewTapLoader.taps(in: json))
        let trust = TapTrust(taps: [], casks: ["https://github.com/user/casks/tool"])
        let index = HomebrewTapLoader.makeIndex(taps: taps, trust: trust, trustedCasks: nil) { _ in nil }

        XCTAssertTrue(index.trusts("user/casks/tool"))
        XCTAssertTrue(index.trusts("user/whole/app"), "brew's own whole-tap trust flag")
        XCTAssertFalse(index.trusts("user/casks/other"))
        XCTAssertTrue(index.trusts("figma"))
    }

    func test_missing_trust_output_means_nothing_is_trusted() {
        XCTAssertEqual(HomebrewTapLoader.trustOrNone(nil), TapTrust(taps: [], casks: []))
        XCTAssertEqual(HomebrewTapLoader.trustOrNone("Error: Unknown command: trust"), TapTrust(taps: [], casks: []))
        XCTAssertEqual(HomebrewTapLoader.trustOrNone(trustJSON).casks, ["macos-fuse-t/cask/fuse-t"])
    }

    private func tapInfoCask(_ token: String, tap: String, version: String) throws -> Cask {
        let json = """
        {"token": "\(token)", "full_token": "\(tap)/\(token)", "tap": "\(tap)", "name": ["\(token)"],
         "homepage": "https://example.com", "version": "\(version)",
         "outdated": false, "deprecated": false, "disabled": false}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var cask = try decoder.decode(Cask.self, from: Data(json.utf8))
        cask.provenance = .tapInfo
        return cask
    }
}
