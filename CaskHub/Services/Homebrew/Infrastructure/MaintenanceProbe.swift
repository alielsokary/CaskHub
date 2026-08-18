//
//  MaintenanceProbe.swift
//  CaskHub
//
//  Created by Ali Elsokary on 19/08/2026.
//

import Foundation

nonisolated struct BrewProbeResult: Equatable, Sendable {
    let exitCode: Int32
    let output: String
}

nonisolated protocol MaintenanceProbing: Sendable {
    func run(_ executable: URL, arguments: [String]) async -> BrewProbeResult?
    func directorySize(at url: URL) async -> Int64
    func removeDirectoryContents(at url: URL) async -> Bool
}

nonisolated struct SystemMaintenanceProbe: MaintenanceProbing {
    @concurrent
    func run(_ executable: URL, arguments: [String]) async -> BrewProbeResult? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // One pipe for both streams: a single read cannot deadlock on a full
        // sibling buffer, and callers treat the output as one transcript anyway.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return BrewProbeResult(
            exitCode: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }

    @concurrent
    func directorySize(at url: URL) async -> Int64 {
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys)
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    @concurrent
    func removeDirectoryContents(at url: URL) async -> Bool {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return false }
        var succeeded = true
        for entry in entries {
            do {
                try fileManager.removeItem(at: entry)
            } catch {
                succeeded = false
            }
        }
        return succeeded
    }
}
