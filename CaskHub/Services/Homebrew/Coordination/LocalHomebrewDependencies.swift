//
//  LocalHomebrewDependencies.swift
//  CaskHub
//
//  Created by Ali Elsokary on 26/07/2026.
//

import Foundation

@MainActor
struct LocalHomebrewDependencies {
    var fileManager: FileManager = .default
    var applicationDirectories: [URL]?
    var processRunner: (any BrewProcessRunning)?
    var commandExecutor: (any HomebrewCommandExecuting)?
    var operationStore: CaskOperationStore?
    var softwareScanner: (any InstalledSoftwareScanning)?
    var applicationLauncher: (any ApplicationLaunching)?
    var brewBinaryProvider: () -> URL? = {
        HomebrewLocator.brewBinaryURL()
    }
    var brewVersionProvider: () async -> String? = {
        await HomebrewVersionLoader().load(
            from: HomebrewLocator.brewBinaryURL()
        )
    }

    func resolvedCommandExecutor() -> any HomebrewCommandExecuting {
        commandExecutor
            ?? SystemHomebrewCommandExecutor(
                processRunner: processRunner ?? SystemBrewProcessRunner()
            )
    }
}
