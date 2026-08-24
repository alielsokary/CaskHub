//
//  AskpassScriptManager.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated enum AskpassScriptError: Error, Equatable, Sendable {
    case executableUnavailable
    case fileSystem(stage: AskpassFailureStage, failureKind: HomebrewFailureKind)

    var stage: AskpassFailureStage {
        switch self {
        case .executableUnavailable: .executable
        case let .fileSystem(stage, _): stage
        }
    }

    var failureKind: HomebrewFailureKind {
        switch self {
        case .executableUnavailable: .askpassUnavailable
        case let .fileSystem(_, failureKind): failureKind
        }
    }

    static func fileSystem(
        _ error: Error,
        stage: AskpassFailureStage
    ) -> Self {
        let nsError = error as NSError
        let isStorageFull = (
            nsError.domain == NSCocoaErrorDomain
                && nsError.code == CocoaError.fileWriteOutOfSpace.rawValue
        ) || (
            nsError.domain == NSPOSIXErrorDomain
                && nsError.code == ENOSPC
        )
        return .fileSystem(
            stage: stage,
            failureKind: isStorageFull ? .storageFull : .askpassUnavailable
        )
    }
}

nonisolated enum AskpassScriptManager {
    // @concurrent: callers are MainActor; these touch disk and must not run there.
    @concurrent
    static func create(
        token: String,
        directory: URL? = nil,
        executableURL: URL? = Bundle.main.executableURL
    ) async throws -> URL {
        guard let executablePath = executableURL?.path else {
            throw AskpassScriptError.executableUnavailable
        }
        let safeToken = token.filter { $0.isLetter || $0.isNumber || "-_+@.".contains($0) }
        let fileManager = FileManager.default
        let destinationDirectory: URL
        if let directory {
            destinationDirectory = directory
        } else {
            let base = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
            destinationDirectory = base.appendingPathComponent(
                "CaskHub",
                isDirectory: true
            )
        }
        let url = destinationDirectory.appendingPathComponent("askpass-\(UUID().uuidString).sh")
        let script = script(
            executablePath: executablePath,
            token: safeToken,
            marker: cancellationMarker(for: url)
        )
        do {
            try fileManager.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw AskpassScriptError.fileSystem(error, stage: .directory)
        }
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AskpassScriptError.fileSystem(error, stage: .script)
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.path
            )
        } catch {
            try? fileManager.removeItem(at: url)
            throw AskpassScriptError.fileSystem(error, stage: .permissions)
        }
        return url
    }

    @concurrent
    static func remove(at url: URL) async {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: cancellationMarker(for: url))
    }

    static func cancellationMarker(for scriptURL: URL) -> URL {
        scriptURL.appendingPathExtension("cancelled")
    }

    static func localError(for error: Error) -> LocalHomebrewError {
        guard let error = error as? AskpassScriptError else {
            return .askpassUnavailable(
                stage: .unknown,
                failureKind: .askpassUnavailable
            )
        }
        return .askpassUnavailable(
            stage: error.stage,
            failureKind: error.failureKind
        )
    }

    private static func script(
        executablePath: String,
        token: String,
        marker: URL
    ) -> String {
        """
        #!/bin/sh
        exec \(shellQuoted(executablePath)) --askpass \(shellQuoted(token)) \
          --askpass-cancel-marker \(shellQuoted(marker.path))
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
