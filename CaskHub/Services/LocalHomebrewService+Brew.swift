//
//  LocalHomebrewService+Brew.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/07/2026.
//

import Foundation

extension LocalHomebrewService {
    // MARK: - Process Helpers

    nonisolated static func ensureAskpassScript(
        token: String,
        directory: URL? = nil,
        executableURL: URL? = Bundle.main.executableURL
    ) -> URL? {
        guard let executablePath = executableURL?.path else { return nil }
        // Interpolated into a shell script — keep only known-safe characters.
        let safeToken = token.filter { $0.isLetter || $0.isNumber || "-_+@.".contains($0) }
        let script = """
        #!/bin/sh
        exec \(shellQuoted(executablePath)) --askpass \(shellQuoted(safeToken))
        """
        let fm = FileManager.default
        let dir: URL
        if let directory {
            dir = directory
        } else {
            guard let base = try? fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) else { return nil }
            dir = base.appendingPathComponent("CaskHub", isDirectory: true)
        }
        let url = dir.appendingPathComponent("askpass-\(UUID().uuidString).sh")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            return nil
        }
        return url
    }

    nonisolated static func removeAskpassScript(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private nonisolated static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
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

    nonisolated static func defaultApplicationDirectories(_ fileManager: FileManager) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
    }

    /// A missing Caskroom isn't an error: fresh brew installs have none until
    /// the first cask lands, and machines without brew have nothing to scan.
    nonisolated static func scanCaskroom(
        fileManager: FileManager,
        applicationDirectories: [URL]? = nil
    ) -> [String: LocalCaskInstallation] {
        guard let caskroomURL = locateCaskroom(fileManager: fileManager) else { return [:] }
        return scanCaskroom(
            at: caskroomURL,
            fileManager: fileManager,
            applicationDirectories: applicationDirectories
                ?? defaultApplicationDirectories(fileManager)
        )
    }

    nonisolated static func scanCaskroom(
        at caskroomURL: URL,
        fileManager: FileManager,
        applicationDirectories: [URL]
    ) -> [String: LocalCaskInstallation] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: caskroomURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var result: [String: LocalCaskInstallation] = [:]
        for entry in entries {
            if let installation = scanCaskEntry(
                entry, fileManager: fileManager, applicationDirectories: applicationDirectories
            ) {
                result[installation.token] = installation
            }
        }
        return result
    }

    /// Version comes from the version-directory name, not the receipt's `source.version`,
    /// which freezes at the original install and never updates after `brew upgrade`.
    private nonisolated static func scanCaskEntry(
        _ entry: URL,
        fileManager: FileManager,
        applicationDirectories: [URL]
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
        let receiptExists = fileManager.fileExists(atPath: receiptURL.path)
        let receipt = receiptExists
            ? (try? Data(contentsOf: receiptURL)).flatMap { try? InstallReceipt(jsonData: $0) }
            : nil

        // No receipt: brew itself refuses to manage the entry ("Cask is not
        // installed"). A receipt that exists but fails to parse is NOT a zombie —
        // a future receipt format must not mass-flag healthy installs.
        let isZombie = !receiptExists || appsGoneEverywhere(
            appNames: receipt?.appBundleNames ?? [],
            versionDir: versionDir,
            fileManager: fileManager,
            applicationDirectories: applicationDirectories
        )

        return LocalCaskInstallation(
            token: entry.lastPathComponent,
            installedVersion: versionDir.lastPathComponent,
            installedAt: try? versionDir.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate,
            appBundleNames: receipt?.appBundleNames ?? [],
            isZombie: isZombie
        )
    }

    /// Filesystem truth for the stranded state: a real .app directory (not the
    /// artifact symlink) parked inside any version dir of the cask's entry.
    nonisolated static func strandedCopyExists(
        in caskroomURL: URL, token: String, fileManager: FileManager
    ) -> Bool {
        let entry = caskroomURL.appendingPathComponent(token)
        guard let versionDirs = try? fileManager.contentsOfDirectory(
            at: entry, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return false }

        for versionDir in versionDirs {
            guard let items = try? fileManager.contentsOfDirectory(
                at: versionDir, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
            ) else { continue }
            for item in items where item.pathExtension == "app" {
                let isSymlink = (try? item.resourceValues(
                    forKeys: [.isSymbolicLinkKey]
                ).isSymbolicLink) == true
                var isDir: ObjCBool = false
                if !isSymlink,
                   fileManager.fileExists(atPath: item.path, isDirectory: &isDir),
                   isDir.boolValue {
                    return true
                }
            }
        }
        return false
    }

    /// True when the receipt names app bundles and none survive — not in any
    /// Applications folder, and no real copy parked in the Caskroom version dir
    /// (fileExists follows symlinks, so a dangling link counts as gone).
    private nonisolated static func appsGoneEverywhere(
        appNames: [String],
        versionDir: URL,
        fileManager: FileManager,
        applicationDirectories: [URL]
    ) -> Bool {
        guard !appNames.isEmpty else { return false }
        let candidateDirs = applicationDirectories + [versionDir]
        return !appNames.contains { name in
            candidateDirs.contains {
                fileManager.fileExists(atPath: $0.appendingPathComponent(name).path)
            }
        }
    }

    /// Executable names in the places CLI tools commonly install to. GUI apps
    /// don't inherit the shell's PATH, so fixed locations beat consulting it.
    nonisolated static func scanBinaryDirectories(
        fileManager: FileManager,
        directories: [URL]? = nil
    ) -> [String: URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        let folders = directories ?? (
            brewPrefixCandidates("bin") + [
                home.appendingPathComponent(".local/bin"),
                home.appendingPathComponent("bin")
            ]
        )
        var paths: [String: URL] = [:]
        for folder in folders {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where fileManager.isExecutableFile(atPath: entry.path) {
                guard let values = try? entry.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                      values.isDirectory != true,
                      let fileSize = values.fileSize,
                      fileSize > 0
                else { continue }
                if paths[entry.lastPathComponent] == nil {
                    paths[entry.lastPathComponent] = entry
                }
            }
        }
        return paths
    }

    private nonisolated static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    // MARK: - Path Discovery

    nonisolated static let customBrewPrefixKey = "customBrewPrefix"

    /// Machine architecture, not build architecture: `hw.optional.arm64` reports
    /// Apple Silicon truthfully even for a process running under Rosetta.
    nonisolated static let isAppleSilicon: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return value == 1
    }()

    private nonisolated static func brewPrefixCandidates(_ relativePath: String) -> [URL] {
        var candidates: [URL] = []
        if let custom = UserDefaults.standard.string(forKey: customBrewPrefixKey), !custom.isEmpty {
            candidates.append(URL(fileURLWithPath: custom).appendingPathComponent(relativePath))
        }
        if let prefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], !prefix.isEmpty {
            candidates.append(URL(fileURLWithPath: prefix).appendingPathComponent(relativePath))
        }
        let standardPrefixes = isAppleSilicon
            ? ["/opt/homebrew", "/usr/local"]
            : ["/usr/local", "/opt/homebrew"]
        for prefix in standardPrefixes {
            candidates.append(URL(fileURLWithPath: prefix).appendingPathComponent(relativePath))
        }
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
