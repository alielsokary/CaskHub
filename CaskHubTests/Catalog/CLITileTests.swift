//
//  CLITileTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 07/10/2026.
//

import AppKit
@testable import CaskHub
import XCTest

@MainActor
final class CLITileTests: XCTestCase {
    func test_command_wrapper_only_cask_is_cli() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var cask = makeCask("steamcmd")
        cask.artifacts = try decoder.decode([ArtifactStanza].self, from: Data(#"""
        [{"command_wrapper":["steamcmd",{"executable":"MacOS/steamcmd.sh"}],"target":"$HOMEBREW_PREFIX/bin/steamcmd"}]
        """#.utf8))

        XCTAssertTrue(cask.isCLI)
    }

    func test_catalog_cli_tokens_mark_package_and_app_casks_as_cli() async throws {
        let categories = CategoryService()
        categories.applyData(try JSONDecoder().decode(CaskCategoryData.self, from: Data(#"""
        {"version":2,"generatedDate":"2026-10-07","categories":{},"tokenToCategory":{},
         "cliTokens":["aptible","cleanmymac-cli"]}
        """#.utf8)))
        let api = MockBrewAPIClient()
        api.casks = [
            makeCask("aptible", packageIdentifiers: ["com.aptible.toolbelt"]),
            makeCask("cleanmymac-cli", appNames: ["CleanMyMac_5_CLI.app"], binaryNames: ["cleanmymac"]),
            makeCask("zoom", packageIdentifiers: ["us.zoom.pkg.videomeeting"])
        ]
        let viewModel = makeViewModel(api: api, categories: categories)

        await viewModel.fetchCasks()

        XCTAssertEqual(viewModel.casks.filter(\.isCLI).map(\.token).sorted(), ["aptible", "cleanmymac-cli"])
    }

    func test_cli_cask_drops_cached_icon_only_when_manifest_omits_it() async throws {
        for (manifest, keepsIcon) in [(Set<String>(), false), (["desktoppr"], true)] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cli-tile-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let disk = IconDiskCache(directory: directory)
            try await disk.store(try png(), token: "desktoppr", generation: 0, fromCaskFlow: true)
            let images = ImageCacheService(session: URLSession(configuration: .ephemeral), diskCache: disk)
            images.knownIconTokens = { manifest }
            var cask = makeCask("desktoppr", packageIdentifiers: ["com.scriptingosx.desktoppr"])
            cask.catalogIsCLI = true

            let image = await images.image(for: cask)
            let stored = await disk.loadData(token: "desktoppr")

            XCTAssertEqual(image != nil, keepsIcon)
            XCTAssertEqual(stored != nil, keepsIcon)
        }
    }

    private func png() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        pixels.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
