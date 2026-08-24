//
//  PackageReceiptResolver.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import Foundation

nonisolated struct PackageReceiptResolver: Sendable {
    typealias Query = @Sendable ([String]) -> String?

    private let query: Query

    init(query: @escaping Query = Self.pkgutilOutput) {
        self.query = query
    }

    /// Matches installed receipts to package-based casks, then confirms that
    /// at least one application from the package payload still exists.
    func scan(
        signatures: [PackageCaskSignature],
        availableAppNames: Set<String>,
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
        var fileLists: [String: String] = [:]
        for receipt in relevantReceipts {
            fileLists[receipt] = query(["--files", receipt])
        }
        return resolve(
            signatures: signatures,
            installedReceipts: installedReceipts,
            packageFileLists: fileLists,
            availableAppNames: availableAppNames,
            homebrewInstalledTokens: homebrewInstalledTokens
        )
    }

    /// Resolves ambiguous package metadata to one cask per physical app.
    func resolve(
        signatures: [PackageCaskSignature],
        installedReceipts: Set<String>,
        packageFileLists: [String: String],
        availableAppNames: Set<String>,
        homebrewInstalledTokens: Set<String> = []
    ) -> [String: ExternalPackageInstallation] {
        var candidates = signatures.compactMap {
            candidate(
                for: $0,
                installedReceipts: installedReceipts,
                packageFileLists: packageFileLists,
                availableAppNames: availableAppNames,
                isHomebrewInstalled: homebrewInstalledTokens.contains($0.token)
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
        installedReceipts: Set<String>,
        packageFileLists: [String: String],
        availableAppNames: Set<String>,
        isHomebrewInstalled: Bool
    ) -> PackageInstallationCandidate? {
        let matchingReceipts = Set(installedReceipts.filter { receipt in
            signature.receiptPatterns.contains {
                Self.identifier(receipt, matches: $0)
            }
        })
        guard !matchingReceipts.isEmpty else { return nil }

        let declaredApps = Set(signature.appNameCandidates)
            .intersection(availableAppNames)
        let payloadApps = Set(matchingReceipts.flatMap { receipt in
            packageFileLists[receipt].map(
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
        let existingApps = declaredApps.union(payloadApps)
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
