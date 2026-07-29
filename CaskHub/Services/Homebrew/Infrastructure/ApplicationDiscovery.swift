//
//  ApplicationDiscovery.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated struct ApplicationDiscovery: Sendable {
    static func defaultDirectories(fileManager: FileManager) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
    }

    func scan(
        fileManager: FileManager,
        directories: [URL]
    ) -> ExternalApplicationScan {
        var applications: [DetectedApplication] = []
        for folder in directories {
            guard let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isPackageKey,
                    .creationDateKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let entry as URL in enumerator {
                guard entry.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                    continue
                }
                // Helper apps embedded inside a top-level app are not independently
                // installed software, even when package metadata is ambiguous.
                enumerator.skipDescendants()
                guard let metadata = metadata(at: entry, fileManager: fileManager) else {
                    continue
                }

                let masReceipt = entry.appendingPathComponent("Contents/_MASReceipt/receipt")
                let dates = try? entry.resourceValues(forKeys: [
                    .creationDateKey,
                    .contentModificationDateKey
                ])
                applications.append(DetectedApplication(
                    url: entry.standardizedFileURL,
                    bundleName: entry.lastPathComponent,
                    bundleIdentifier: metadata.bundleIdentifier,
                    isMacAppStore: fileManager.fileExists(atPath: masReceipt.path),
                    isDirectlyInApplicationDirectory:
                        entry.deletingLastPathComponent().standardizedFileURL
                        == folder.standardizedFileURL,
                    installedAt: dates?.creationDate,
                    lastUpdatedAt: dates?.contentModificationDate
                ))
            }
        }
        return ExternalApplicationScan(applications: applications)
    }

    /// A directory ending in `.app` is not necessarily launchable. Partial
    /// installer leftovers can retain that shape after their executable and
    /// Info.plist are removed, so validate both.
    func metadata(
        at appURL: URL,
        fileManager: FileManager
    ) -> ApplicationBundleMetadata? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let executable = info["CFBundleExecutable"] as? String,
              !executable.isEmpty
        else { return nil }

        let executableURL = appURL.appendingPathComponent("Contents/MacOS/\(executable)")
        guard fileManager.isExecutableFile(atPath: executableURL.path) else { return nil }
        return ApplicationBundleMetadata(bundleIdentifier: info["CFBundleIdentifier"] as? String)
    }
}

nonisolated struct ApplicationOwnershipResolver: Sendable {
    /// Assigns each directly installed application to at most one cask.
    /// Installed Homebrew casks claim their bundles before external
    /// applications are considered.
    func resolve(
        signatures: [ApplicationCaskSignature],
        applications: [DetectedApplication],
        installedCasks: [String: LocalCaskInstallation]
    ) -> [String: DetectedApplication] {
        guard !signatures.isEmpty else { return [:] }

        let signaturesByToken = Dictionary(
            signatures.map { ($0.token, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let installedBundleNames = Set(installedCasks.values.flatMap { installation in
            let catalogNames = signaturesByToken[installation.token]?.appBundleNames ?? []
            return installation.appBundleNames + Array(catalogNames)
        }.map(Self.normalizedApplicationName))
        let installedTokens = Set(installedCasks.keys)
        var signaturesByBundleName: [String: [ApplicationCaskSignature]] = [:]
        for signature in signatures where !installedTokens.contains(signature.token) {
            for bundleName in signature.appBundleNames {
                signaturesByBundleName[
                    Self.normalizedApplicationName(bundleName),
                    default: []
                ].append(signature)
            }
        }

        var owners: [String: DetectedApplication] = [:]
        for application in applications where
            !application.isMacAppStore && application.isDirectlyInApplicationDirectory {
            let normalizedName = Self.normalizedApplicationName(application.bundleName)
            guard !installedBundleNames.contains(normalizedName) else { continue }

            let candidates = signaturesByBundleName[normalizedName] ?? []
            guard let owner = Self.owner(for: application, candidates: candidates) else {
                continue
            }
            owners[owner.token] = application
        }
        return owners
    }

    private static func owner(
        for application: DetectedApplication,
        candidates: [ApplicationCaskSignature]
    ) -> ApplicationCaskSignature? {
        if candidates.count == 1 { return candidates[0] }
        guard candidates.count > 1,
              let identifier = application.bundleIdentifier?.lowercased()
        else { return nil }

        let exactMatches = candidates.filter { signature in
            signature.bundleIdentifiers.contains { $0.lowercased() == identifier }
        }
        return exactMatches.count == 1 ? exactMatches[0] : nil
    }

    private static func normalizedApplicationName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

nonisolated enum ApplicationIdentityMatcher {
    static func applicationBundleIdentifier(
        _ identifier: String,
        matchesAny candidates: [String]
    ) -> Bool {
        let actual = identifier.lowercased().split(separator: ".").map(String.init)
        return candidates.contains { candidate in
            let expected = candidate.lowercased().split(separator: ".").map(String.init)
            if actual == expected { return true }
            return zip(actual, expected).prefix { pair in
                pair.0 == pair.1
            }.count >= 3
        }
    }

    static func bundleIdentifier(
        _ bundleIdentifier: String,
        matchesPackageIdentifiers packageIdentifiers: [String]
    ) -> Bool {
        guard let bundleVendor = reverseDNSVendorPrefix(bundleIdentifier) else { return false }
        return packageIdentifiers.contains {
            reverseDNSVendorPrefix($0) == bundleVendor
        }
    }

    private static func reverseDNSVendorPrefix(_ identifier: String) -> String? {
        let components = identifier.lowercased().split(separator: ".")
        guard components.count >= 2 else { return nil }
        return components.prefix(2).joined(separator: ".")
    }
}
