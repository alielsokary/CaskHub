//
//  AskpassScriptManager.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated enum AskpassScriptManager {
    static func create(
        token: String,
        directory: URL? = nil,
        executableURL: URL? = Bundle.main.executableURL
    ) -> URL? {
        guard let executablePath = executableURL?.path else { return nil }
        let safeToken = token.filter {
            $0.isLetter || $0.isNumber || "-_+@.".contains($0)
        }
        let script = """
        #!/bin/sh
        exec \(shellQuoted(executablePath)) --askpass \(shellQuoted(safeToken))
        """
        let fileManager = FileManager.default
        let destinationDirectory: URL
        if let directory {
            destinationDirectory = directory
        } else {
            guard let base = try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) else { return nil }
            destinationDirectory = base.appendingPathComponent(
                "CaskHub",
                isDirectory: true
            )
        }
        let url = destinationDirectory
            .appendingPathComponent("askpass-\(UUID().uuidString).sh")
        do {
            try fileManager.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
            try script.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.path
            )
        } catch {
            return nil
        }
        return url
    }

    static func remove(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
