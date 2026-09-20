//
//  PackageReceiptResolver.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated struct PackageReceiptResolver: Sendable {
    typealias Query = @Sendable ([String]) -> String?

    struct ReceiptLocation: Sendable {
        let volume: URL
        let installLocation: String
    }

    struct Receipt: Sendable {
        let files: String?
        let location: ReceiptLocation?
    }

    private let query: Query

    init(query: @escaping Query = Self.pkgutilOutput) {
        self.query = query
    }

    /// Matches installed receipts to package-based casks, then confirms that
    /// at least one application from the package payload still exists.
    func scan(
        signatures: [PackageCaskSignature],
        availableAppNames: Set<String>,
        applications: [DetectedApplication],
        homebrewInstalledTokens: Set<String> = []
    ) -> [String: ExternalPackageInstallation] {
        guard !signatures.isEmpty,
              let receiptOutput = query(["--pkgs"])
        else { return [:] }

        let installedReceipts = Set(
            receiptOutput.split(whereSeparator: \.isNewline).map(String.init)
        )
        let relevantReceipts = installedReceipts.filter { receipt in
            signatures.contains { signature in
                signature.receiptPatterns.contains {
                    Self.identifier(receipt, matches: $0)
                }
            }
        }
        var receipts: [String: Receipt] = [:]
        let conditionalReceipts = Set(signatures.flatMap(\.receiptCandidates).map(\.packageIdentifier))
        for receipt in relevantReceipts {
            let location = conditionalReceipts.contains(receipt)
                ? query(["--pkg-info-plist", receipt]).flatMap {
                    Self.receiptLocation($0, identifier: receipt)
                } : nil
            receipts[receipt] = Receipt(files: query(["--files", receipt]), location: location)
        }
        return resolve(
            signatures: signatures,
            receipts: receipts,
            availableAppNames: availableAppNames,
            applications: applications,
            homebrewInstalledTokens: homebrewInstalledTokens
        )
    }

    /// Resolves ambiguous package metadata to one cask per physical app.
    func resolve(
        signatures: [PackageCaskSignature],
        receipts: [String: Receipt],
        availableAppNames: Set<String>,
        applications: [DetectedApplication],
        homebrewInstalledTokens: Set<String> = []
    ) -> [String: ExternalPackageInstallation] {
        let applicationsByName = Dictionary(
            grouping: applications.filter { !$0.isMacAppStore && $0.isDirectlyInApplicationDirectory },
            by: \.bundleName
        )
        let verifiedCandidates = verifiedReceiptCandidates(
            signatures: signatures, receipts: receipts,
            applicationsByName: applicationsByName, homebrewInstalledTokens: homebrewInstalledTokens
        )
        var candidates = signatures.compactMap { signature -> PackageInstallationCandidate? in
            let rejectedNames = signature.verifiedBundleIdentifiersByName.keys.filter { name in
                let matches = applicationsByName[name] ?? []
                guard matches.count == 1, let identifier = matches.first?.bundleIdentifier else { return true }
                return !ApplicationIdentityMatcher.applicationBundleIdentifier(
                    identifier, matchesAny: signature.verifiedBundleIdentifiersByName[name] ?? []
                )
            }
            let conditionalNames = Set(signature.receiptCandidates.map(\.bundleName))
            return candidate(
                for: signature,
                receipts: receipts,
                availableAppNames: availableAppNames.subtracting(rejectedNames).subtracting(conditionalNames),
                receiptVerifiedApps: verifiedCandidates[signature.token] ?? [],
                isHomebrewInstalled: homebrewInstalledTokens.contains(signature.token)
            )
        }
        candidates.sort {
            if $0.isHomebrewInstalled != $1.isHomebrewInstalled {
                return $0.isHomebrewInstalled
            }
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
                appBundleNames: unclaimedApps.sorted()
            )
            claimedApps.formUnion(unclaimedApps)
        }
        return result
    }

    private func candidate(
        for signature: PackageCaskSignature,
        receipts: [String: Receipt],
        availableAppNames: Set<String>,
        receiptVerifiedApps: Set<String>,
        isHomebrewInstalled: Bool
    ) -> PackageInstallationCandidate? {
        let matchingReceipts = Set(receipts.keys.filter { receipt in
            signature.receiptPatterns.contains {
                Self.identifier(receipt, matches: $0)
            }
        })
        guard !matchingReceipts.isEmpty else { return nil }

        let declaredApps = Set(signature.appNameCandidates)
            .intersection(availableAppNames)
        let payloadApps = Set(matchingReceipts.flatMap { receipt in
            receipts[receipt]?.files.map(
                Self.appBundleNames(inPackageFileList:)
            ) ?? []
        })
        .intersection(availableAppNames)
        .filter {
            Self.payloadAppName(
                $0,
                matches: signature.appNameCandidates,
                allowingVariantDifference: isHomebrewInstalled
            )
        }
        let existingApps = declaredApps.union(payloadApps).union(receiptVerifiedApps)
        guard !existingApps.isEmpty else { return nil }

        let score = existingApps.map { appName in
            (declaredApps.contains(appName) ? 1000 : 0)
                + Self.nameMatchScore(
                    appName,
                    displayName: signature.displayName
                )
        }.max() ?? 0
        return PackageInstallationCandidate(
            signature: signature,
            appBundleNames: existingApps,
            score: score,
            isHomebrewInstalled: isHomebrewInstalled
        )
    }

    static func payloadAppName(
        _ appName: String,
        matches candidates: [String],
        allowingVariantDifference: Bool = false
    ) -> Bool {
        let actualTokens = nameTokens(appName)
        let variantTokens: Set = [
            "alpha", "beta", "canary", "dev", "developer", "nightly", "preview", "rc"
        ]
        return candidates.contains { candidate in
            let candidateTokens = nameTokens(candidate)
            // A Caskroom entry establishes ownership even when the vendor adds
            // a variant suffix without changing the Homebrew token. External
            // package detection remains variant-exact.
            if !allowingVariantDifference {
                guard actualTokens.intersection(variantTokens)
                    == candidateTokens.intersection(variantTokens)
                else { return false }
            }
            return actualTokens.isSubset(of: candidateTokens)
                || candidateTokens.isSubset(of: actualTokens)
        }
    }

    static func identifier(_ identifier: String, matches pattern: String) -> Bool {
        fnmatch(pattern, identifier, 0) == 0
    }

    static func appBundleNames(inPackageFileList output: String) -> Set<String> {
        Set(output.split(whereSeparator: \.isNewline).compactMap { line in
            line.split(separator: "/").first {
                $0.hasSuffix(".app")
            }.map(String.init)
        })
    }

    private static func nameMatchScore(
        _ appName: String,
        displayName: String
    ) -> Int {
        let actual = nameTokens(appName)
        let expected = nameTokens(displayName)
        if actual == expected { return 100 }
        if expected.isSubset(of: actual) {
            return 80 - (actual.count - expected.count)
        }
        if actual.isSubset(of: expected) {
            return 60 - (expected.count - actual.count)
        }
        return actual.intersection(expected).count * 10
    }

    private static func nameTokens(_ name: String) -> Set<String> {
        Set(name.lowercased().split {
            !$0.isLetter && !$0.isNumber
        }.map(String.init))
    }

    private static func pkgutilOutput(arguments: [String]) -> String? {
        guard let result = ProcessCapture.capture(
            URL(fileURLWithPath: "/usr/sbin/pkgutil"),
            arguments: arguments
        ), result.status == 0 else { return nil }
        return result.output
    }
}

extension PackageReceiptResolver {
    private static func receiptLocation(_ output: String, identifier: String) -> ReceiptLocation? {
        guard let plist = try? PropertyListSerialization.propertyList(from: Data(output.utf8), format: nil),
              let values = plist as? [String: Any], values["pkgid"] as? String == identifier,
              let volume = values["volume"] as? String, volume.hasPrefix("/"),
              let location = values["install-location"] as? String,
              !location.split(separator: "/").contains("..")
        else { return nil }
        return ReceiptLocation(volume: URL(fileURLWithPath: volume), installLocation: location)
    }

    private func verifiedReceiptCandidates(
        signatures: [PackageCaskSignature], receipts: [String: Receipt],
        applicationsByName: [String: [DetectedApplication]], homebrewInstalledTokens: Set<String>
    ) -> [String: Set<String>] {
        var claims: [String: Set<String>] = [:]
        for signature in signatures {
            for identity in signature.receiptCandidates where
                signature.receiptPatterns.contains(where: { Self.identifier(identity.packageIdentifier, matches: $0) })
                    && receipts[identity.packageIdentifier] != nil {
                guard let applications = applicationsByName[identity.bundleName], applications.count == 1,
                      let application = applications.first,
                      let location = receipts[identity.packageIdentifier]?.location,
                      let files = receipts[identity.packageIdentifier]?.files,
                      Self.verifies(identity, application: application, location: location, files: files)
                else { continue }
                claims[identity.bundleName, default: []].insert(signature.token)
            }
        }
        var result: [String: Set<String>] = [:]
        for (name, tokens) in claims {
            let installed = tokens.intersection(homebrewInstalledTokens)
            let owners = installed.isEmpty ? tokens : installed
            guard owners.count == 1, let owner = owners.first else { continue }
            result[owner, default: []].insert(name)
        }
        return result
    }

    private static func verifies(
        _ identity: PackageApplicationIdentity, application: DetectedApplication,
        location: ReceiptLocation, files: String
    ) -> Bool {
        guard identity.bundleName.hasSuffix(".app"), !identity.bundleName.contains("/"),
              identity.installedPath == "/Applications/\(identity.bundleName)",
              let identifier = application.bundleIdentifier,
              ApplicationIdentityMatcher.applicationBundleIdentifier(identifier, matchesAny: [identity.bundleIdentifier]),
              application.url.standardizedFileURL == location.volume
                .appendingPathComponent(String(identity.installedPath.dropFirst())).standardizedFileURL
        else { return false }
        let installRoot = URL(fileURLWithPath: "/").appendingPathComponent(location.installLocation)
        let expectedPlist = identity.installedPath + "/Contents/Info.plist"
        return files.split(whereSeparator: \.isNewline).contains { line in
            guard !line.hasPrefix("/"), !line.split(separator: "/").contains("..") else { return false }
            return installRoot.appendingPathComponent(String(line)).standardizedFileURL.path == expectedPlist
        }
    }
}
