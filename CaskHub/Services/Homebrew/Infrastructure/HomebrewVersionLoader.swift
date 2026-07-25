//
//  HomebrewVersionLoader.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated struct HomebrewVersionLoader: Sendable {
    @concurrent
    func load(from brewURL: URL?) async -> String? {
        guard let brewURL else { return nil }
        let process = Process()
        process.executableURL = brewURL
        process.arguments = ["--version"]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let firstLine = String(data: data, encoding: .utf8)?
                .split(separator: "\n").first
        else { return nil }
        return firstLine.split(separator: " ").last.map(String.init)
    }
}
