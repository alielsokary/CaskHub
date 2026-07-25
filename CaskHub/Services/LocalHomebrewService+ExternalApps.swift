//
//  LocalHomebrewService+ExternalApps.swift
//  CaskHub
//

import Foundation

extension LocalHomebrewService {
    /// The catalog provides app identity and package receipt metadata needed to
    /// associate software already on the Mac with exactly one Homebrew cask.
    func updatePackageCatalog(_ casks: [Cask]) async {
        updateCatalogSignatures(casks)
        packageCatalogGeneration &+= 1
        let packageGeneration = packageCatalogGeneration

        let appSignatures = applicationCaskSignatures
        let catalog = installationCatalog
        let packageSignatures = packageCaskSignatures
        let installed = installedCasks
        let binaryPaths = externalBinaryPaths
        let fm = fileManager
        let appDirs = applicationDirectories
        let result = await Task.detached(priority: .userInitiated) {
            let applications = Self.scanApplications(fileManager: fm, directories: appDirs)
            let packages = packageSignatures.isEmpty ? [:] : Self.scanExternalPackageInstallations(
                signatures: packageSignatures,
                availableAppNames: applications.nonStoreNames
            )
            let owners = Self.resolveExternalApplicationOwners(
                signatures: appSignatures,
                applications: applications.applications,
                installedCasks: installed
            )
            let index = Self.buildInstallationIndex(
                catalog: catalog,
                applications: applications.applications,
                binaryPaths: binaryPaths,
                installedCasks: installed
            )
            return (applications, packages, owners, index)
        }.value
        guard packageGeneration == packageCatalogGeneration else { return }

        externalAppNames = result.0.adoptableNames
        macAppStoreAppNames = result.0.macAppStoreNames
        macAppStoreBundleIdentifiers = result.0.macAppStoreBundleIdentifiers
        detectedApplications = result.0.applications
        externalApplicationOwners = result.2
        externalPackageInstallations = result.1
        installationIndex = result.3
    }

    private func updateCatalogSignatures(_ casks: [Cask]) {
        caskDisplayNames = casks.reduce(into: [:]) { names, cask in
            names[cask.token] = cask.displayName
        }
        applicationCaskSignatures = casks.compactMap { cask in
            guard !cask.appArtifactNames.isEmpty else { return nil }
            return ApplicationCaskSignature(
                token: cask.token,
                appBundleNames: Set(cask.appArtifactNames),
                bundleIdentifiers: Set(cask.applicationBundleIdentifiers)
            )
        }
        let storeSignatures: [MacAppStoreCaskSignature] = casks.compactMap { cask in
            let bundleNames = Set(cask.appArtifactNames + cask.packageAppNameCandidates)
            guard !bundleNames.isEmpty else { return nil }
            return MacAppStoreCaskSignature(
                token: cask.token,
                bundleNames: bundleNames,
                hasPackageArtifact: cask.hasPackageArtifact,
                applicationBundleIdentifiers: cask.applicationBundleIdentifiers,
                packageIdentifiers: cask.packageIdentifiers
            )
        }
        let binarySignatures: [BinaryCaskSignature] = casks.compactMap { cask in
            guard !cask.binaryArtifactNames.isEmpty else { return nil }
            return BinaryCaskSignature(
                token: cask.token,
                binaryNames: cask.binaryArtifactNames
            )
        }
        installationCatalog = CaskInstallationCatalog(
            tokens: Set(casks.map(\.token)),
            macAppStoreSignatures: storeSignatures,
            binarySignatures: binarySignatures
        )
        packageCaskSignatures = casks.compactMap { cask in
            guard cask.hasPackageArtifact, !cask.packageIdentifiers.isEmpty else { return nil }
            return PackageCaskSignature(
                token: cask.token,
                displayName: cask.displayName,
                receiptPatterns: cask.packageIdentifiers,
                appNameCandidates: cask.packageAppNameCandidates
            )
        }
    }

    nonisolated static func scanApplications(
        fileManager: FileManager,
        directories: [URL]? = nil
    ) -> ExternalApplicationScan {
        let folders = directories ?? [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var applications: [DetectedApplication] = []
        for folder in folders {
            guard let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let entry as URL in enumerator {
                guard entry.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                    continue
                }
                // Never mistake helper apps embedded inside a top-level app for
                // independently installed software, even if package metadata is odd.
                enumerator.skipDescendants()
                guard let metadata = applicationBundleMetadata(
                    at: entry, fileManager: fileManager
                ) else { continue }

                let masReceipt = entry.appendingPathComponent("Contents/_MASReceipt/receipt")
                applications.append(DetectedApplication(
                    url: entry.standardizedFileURL,
                    bundleName: entry.lastPathComponent,
                    bundleIdentifier: metadata.bundleIdentifier,
                    isMacAppStore: fileManager.fileExists(atPath: masReceipt.path),
                    isDirectlyInApplicationDirectory:
                        entry.deletingLastPathComponent().standardizedFileURL
                        == folder.standardizedFileURL
                ))
            }
        }
        return ExternalApplicationScan(applications: applications)
    }

    /// Assigns each directly installed application to at most one cask.
    /// Bundle names identify ordinary apps; shared names require one exact
    /// bundle-identifier match. Installed Homebrew casks claim their bundles
    /// before external applications are considered.
    nonisolated static func resolveExternalApplicationOwners(
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
        }.map { normalizedApplicationName($0) })
        let installedTokens = Set(installedCasks.keys)
        var signaturesByBundleName: [String: [ApplicationCaskSignature]] = [:]
        for signature in signatures where !installedTokens.contains(signature.token) {
            for bundleName in signature.appBundleNames {
                signaturesByBundleName[
                    normalizedApplicationName(bundleName),
                    default: []
                ].append(signature)
            }
        }

        var owners: [String: DetectedApplication] = [:]
        for application in applications where
            !application.isMacAppStore && application.isDirectlyInApplicationDirectory {
            let normalizedName = normalizedApplicationName(application.bundleName)
            guard !installedBundleNames.contains(normalizedName) else { continue }

            let candidates = signaturesByBundleName[normalizedName] ?? []
            guard let owner = externalApplicationOwner(
                for: application, candidates: candidates
            ) else { continue }
            owners[owner.token] = application
        }
        return owners
    }

    private nonisolated static func externalApplicationOwner(
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

    private nonisolated static func normalizedApplicationName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// A directory ending in `.app` is not necessarily launchable. Partial
    /// installer leftovers can retain that shape after their executable and
    /// Info.plist are removed, so validate both before exposing Open/Adopt.
    nonisolated static func applicationBundleMetadata(
        at appURL: URL,
        fileManager: FileManager
    ) -> ApplicationBundleMetadata? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any],
              let executable = info["CFBundleExecutable"] as? String,
              !executable.isEmpty
        else { return nil }

        let executableURL = appURL.appendingPathComponent("Contents/MacOS/\(executable)")
        guard fileManager.isExecutableFile(atPath: executableURL.path) else { return nil }
        return ApplicationBundleMetadata(bundleIdentifier: info["CFBundleIdentifier"] as? String)
    }

    /// Matches installed package receipts to package-based casks, then confirms
    /// that at least one application from the package payload still exists.
    /// Package receipts alone are insufficient because macOS keeps stale receipts
    /// after an application is manually removed.
    nonisolated static func scanExternalPackageInstallations(
        signatures: [PackageCaskSignature],
        availableAppNames: Set<String>
    ) -> [String: ExternalPackageInstallation] {
        guard !signatures.isEmpty,
              let receiptOutput = pkgutilOutput(arguments: ["--pkgs"])
        else { return [:] }

        let installedReceipts = Set(receiptOutput.split(whereSeparator: \.isNewline).map(String.init))
        let relevantReceipts = installedReceipts.filter { receipt in
            signatures.contains { signature in
                signature.receiptPatterns.contains { packageIdentifier(receipt, matches: $0) }
            }
        }
        var fileLists: [String: String] = [:]
        for receipt in relevantReceipts {
            fileLists[receipt] = pkgutilOutput(arguments: ["--files", receipt])
        }
        return resolveExternalPackageInstallations(
            signatures: signatures,
            installedReceipts: installedReceipts,
            packageFileLists: fileLists,
            availableAppNames: availableAppNames
        )
    }

    /// Resolves ambiguous package metadata to one cask per physical app. Some
    /// casks (notably both Zoom variants) intentionally share the same receipt
    /// and installed bundle, so showing both would double-count one installation.
    nonisolated static func resolveExternalPackageInstallations(
        signatures: [PackageCaskSignature],
        installedReceipts: Set<String>,
        packageFileLists: [String: String],
        availableAppNames: Set<String>
    ) -> [String: ExternalPackageInstallation] {
        var candidates: [PackageInstallationCandidate] = []

        for signature in signatures {
            let matchingReceipts = Set(installedReceipts.filter { receipt in
                signature.receiptPatterns.contains { packageIdentifier(receipt, matches: $0) }
            })
            guard !matchingReceipts.isEmpty else { continue }

            let declaredApps = Set(signature.appNameCandidates).intersection(availableAppNames)
            let payloadApps = Set(matchingReceipts.flatMap { receipt in
                packageFileLists[receipt].map(appBundleNames(inPackageFileList:)) ?? []
            })
            .intersection(availableAppNames)
            .filter { packagePayloadAppName($0, matches: signature.appNameCandidates) }
            let existingApps = declaredApps.union(payloadApps)
            guard !existingApps.isEmpty else { continue }

            let score = existingApps.map { appName in
                (declaredApps.contains(appName) ? 1000 : 0)
                    + packageNameMatchScore(appName, displayName: signature.displayName)
            }.max() ?? 0
            candidates.append(PackageInstallationCandidate(
                signature: signature, receiptIdentifiers: matchingReceipts,
                appBundleNames: existingApps,
                score: score
            ))
        }

        candidates.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.signature.token.count != $1.signature.token.count {
                return $0.signature.token.count < $1.signature.token.count
            }
            return $0.signature.token < $1.signature.token
        }

        var claimedApps: Set<String> = []
        var result: [String: ExternalPackageInstallation] = [:]
        for candidate in candidates {
            let unclaimedApps = candidate.appBundleNames.subtracting(claimedApps)
            guard !unclaimedApps.isEmpty else { continue }
            result[candidate.signature.token] = ExternalPackageInstallation(
                receiptIdentifiers: candidate.receiptIdentifiers,
                appBundleNames: unclaimedApps.sorted()
            )
            claimedApps.formUnion(unclaimedApps)
        }
        return result
    }

    nonisolated static func packagePayloadAppName(
        _ appName: String,
        matches candidates: [String]
    ) -> Bool {
        let actualTokens = appNameTokens(appName)
        let variantTokens: Set = [
            "alpha", "beta", "canary", "dev", "developer", "nightly", "preview", "rc"
        ]
        return candidates.contains { candidate in
            let candidateTokens = appNameTokens(candidate)
            guard actualTokens.intersection(variantTokens)
                == candidateTokens.intersection(variantTokens)
            else { return false }
            return actualTokens.isSubset(of: candidateTokens)
                || candidateTokens.isSubset(of: actualTokens)
        }
    }

    private nonisolated static func packageNameMatchScore(
        _ appName: String,
        displayName: String
    ) -> Int {
        let actual = appNameTokens(appName)
        let expected = appNameTokens(displayName)
        if actual == expected { return 100 }
        if expected.isSubset(of: actual) { return 80 - (actual.count - expected.count) }
        if actual.isSubset(of: expected) { return 60 - (expected.count - actual.count) }
        return actual.intersection(expected).count * 10
    }

    private nonisolated static func appNameTokens(_ name: String) -> Set<String> {
        Set(name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    nonisolated static func packageIdentifier(_ identifier: String, matches pattern: String) -> Bool {
        guard pattern.contains("*") || pattern.contains("?") else { return identifier == pattern }
        var expression = NSRegularExpression.escapedPattern(for: pattern)
        expression = expression
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        guard let regex = try? NSRegularExpression(pattern: "^\(expression)$") else { return false }
        let range = NSRange(identifier.startIndex..., in: identifier)
        return regex.firstMatch(in: identifier, range: range) != nil
    }

    nonisolated static func appBundleNames(inPackageFileList output: String) -> Set<String> {
        Set(output.split(whereSeparator: \.isNewline).compactMap { line in
            line.split(separator: "/").first { $0.hasSuffix(".app") }.map(String.init)
        })
    }

    private nonisolated static func pkgutilOutput(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
