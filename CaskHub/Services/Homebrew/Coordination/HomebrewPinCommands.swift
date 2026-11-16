//
//  HomebrewPinCommands.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/11/2026.
//

import Foundation

@MainActor
struct HomebrewPinCommands {
    let commandExecutor: any HomebrewCommandExecuting
    let brewBinaryProvider: () -> URL?

    func run(pinned: Bool, reference: String) async throws {
        let brewURL = try HomebrewLocator.validatedBrewURL(brewBinaryProvider())
        let arguments = [pinned ? "pin" : "unpin", "--cask", reference]
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_ASK"] = "1"
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        let result = try await commandExecutor.execute(
            HomebrewCommandRequest(
                token: "caskhub-pin:\(reference)",
                executableURL: brewURL,
                arguments: arguments,
                environment: environment
            ),
            onStart: {},
            onChunk: { _ in }
        )
        guard result.exitCode != 0 else { return }
        throw LocalHomebrewError.brewCommandFailed(
            args: arguments,
            exitCode: result.exitCode,
            stderr: HomebrewOutputDiagnostics.make(from: result.output)
        )
    }
}
