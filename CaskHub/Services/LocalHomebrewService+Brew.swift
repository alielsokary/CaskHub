//
//  LocalHomebrewService+Brew.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/07/2026.
//

import Foundation

extension LocalHomebrewService {
    // MARK: - Process Helpers

    nonisolated static func ensureAskpassScript(token: String) -> URL? {
        guard let executablePath = Bundle.main.executableURL?.path else { return nil }
        // Interpolated into a shell script — keep only known-safe characters.
        let safeToken = token.filter { $0.isLetter || $0.isNumber || "-_+@.".contains($0) }
        let script = """
        #!/bin/sh
        exec "\(executablePath)" --askpass "\(safeToken)"
        """
        let fm = FileManager.default
        guard let base = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("CaskHub", isDirectory: true)
        let url = dir.appendingPathComponent("askpass.sh")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            return nil
        }
        return url
    }

    nonisolated static func signalTree(pid: Int32, signal: Int32) {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", "\(pid)"]
        let stdout = Pipe()
        pgrep.standardOutput = stdout
        pgrep.standardError = FileHandle.nullDevice
        if (try? pgrep.run()) != nil {
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            pgrep.waitUntilExit()
            let children = String(data: data, encoding: .utf8)?
                .split(whereSeparator: \.isNewline)
                .compactMap { Int32($0) } ?? []
            for child in children {
                signalTree(pid: child, signal: signal)
            }
        }
        kill(pid, signal)
    }

    nonisolated static func cleanupIncompleteDownloads(since cutoff: Date) {
        let fm = FileManager.default
        let cacheURL: URL
        if let override = ProcessInfo.processInfo.environment["HOMEBREW_CACHE"], !override.isEmpty {
            cacheURL = URL(fileURLWithPath: override)
        } else {
            cacheURL = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/Homebrew")
        }
        let downloadsURL = cacheURL.appendingPathComponent("downloads", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for file in files where modificationDate(of: file) >= cutoff {
            try? fm.removeItem(at: file)
        }
    }

    nonisolated static func fetchBrewVersion() async -> String? {
        guard let brewURL = locateBrewBinary() else { return nil }
        return await Task.detached(priority: .utility) {
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
        }.value
    }

    // MARK: - Filesystem Scanning

    nonisolated static func scanCaskroom(
        fileManager: FileManager
    ) -> Result<[String: LocalCaskInstallation], LocalHomebrewError> {
        guard let caskroomURL = locateCaskroom(fileManager: fileManager) else {
            return .failure(.caskroomNotFound)
        }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: caskroomURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .success([:])
        }

        var result: [String: LocalCaskInstallation] = [:]
        for entry in entries {
            if let installation = scanCaskEntry(entry, fileManager: fileManager) {
                result[installation.token] = installation
            }
        }
        return .success(result)
    }

    /// Version comes from the version-directory name, not the receipt's `source.version`,
    /// which freezes at the original install and never updates after `brew upgrade`.
    private nonisolated static func scanCaskEntry(
        _ entry: URL,
        fileManager: FileManager
    ) -> LocalCaskInstallation? {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue,
              let subDirs = try? fileManager.contentsOfDirectory(
                  at: entry,
                  includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              )
        else { return nil }

        let versionDirs = subDirs.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard let versionDir = versionDirs.max(by: {
            modificationDate(of: $0) < modificationDate(of: $1)
        }) else { return nil }

        let receiptURL = entry
            .appendingPathComponent(".metadata", isDirectory: true)
            .appendingPathComponent("INSTALL_RECEIPT.json")
        let receipt = (try? Data(contentsOf: receiptURL))
            .flatMap { try? InstallReceipt(jsonData: $0) }

        return LocalCaskInstallation(
            token: entry.lastPathComponent,
            installedVersion: versionDir.lastPathComponent,
            installedAt: try? versionDir.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate,
            appBundleNames: receipt?.appBundleNames ?? []
        )
    }

    /// Executable names in the places CLI tools commonly install to. GUI apps
    /// don't inherit the shell's PATH, so fixed locations beat consulting it.
    nonisolated static func scanBinaryDirectories(fileManager: FileManager) -> Set<String> {
        let home = fileManager.homeDirectoryForCurrentUser
        let folders = [
            URL(fileURLWithPath: "/usr/local/bin"),
            home.appendingPathComponent(".local/bin"),
            home.appendingPathComponent("bin")
        ]
        var names: Set<String> = []
        for folder in folders {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where fileManager.isExecutableFile(atPath: entry.path) {
                names.insert(entry.lastPathComponent)
            }
        }
        return names
    }

    nonisolated static func scanApplications(fileManager: FileManager) -> Set<String> {
        let folders = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var names: Set<String> = []
        for folder in folders {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where entry.pathExtension == "app" {
                // Mac App Store apps carry a receipt; adopting those would fight MAS updates.
                let masReceipt = entry.appendingPathComponent("Contents/_MASReceipt/receipt")
                guard !fileManager.fileExists(atPath: masReceipt.path) else { continue }
                names.insert(entry.lastPathComponent)
            }
        }
        return names
    }

    private nonisolated static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    // MARK: - Path Discovery

    nonisolated static let customBrewPrefixKey = "customBrewPrefix"

    private nonisolated static func brewPrefixCandidates(_ relativePath: String) -> [URL] {
        var candidates: [URL] = []
        if let custom = UserDefaults.standard.string(forKey: customBrewPrefixKey), !custom.isEmpty {
            candidates.append(URL(fileURLWithPath: custom).appendingPathComponent(relativePath))
        }
        if let prefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], !prefix.isEmpty {
            candidates.append(URL(fileURLWithPath: prefix).appendingPathComponent(relativePath))
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew").appendingPathComponent(relativePath))
        candidates.append(URL(fileURLWithPath: "/usr/local").appendingPathComponent(relativePath))
        return candidates
    }

    nonisolated static func locateCaskroom(fileManager: FileManager) -> URL? {
        brewPrefixCandidates("Caskroom").first { fileManager.fileExists(atPath: $0.path) }
    }

    /// Resolves a user's picker selection to a brew prefix. Accepts the brew
    /// binary itself, a prefix folder, or the bin folder inside it.
    nonisolated static func brewPrefix(fromSelection url: URL) -> String? {
        let fm = FileManager.default
        if url.lastPathComponent == "brew", fm.isExecutableFile(atPath: url.path) {
            return url.deletingLastPathComponent().deletingLastPathComponent().path
        }
        if fm.isExecutableFile(atPath: url.appendingPathComponent("bin/brew").path) {
            return url.path
        }
        if fm.isExecutableFile(atPath: url.appendingPathComponent("brew").path) {
            return url.deletingLastPathComponent().path
        }
        return nil
    }

    nonisolated static func locateBrewBinary() -> URL? {
        brewPrefixCandidates("bin/brew").first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
