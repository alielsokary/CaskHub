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
        availableAppNames: Set<String>
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
            availableAppNames: availableAppNames
        )
    }

    /// Resolves ambiguous package metadata to one cask per physical app.
    func resolve(
        signatures: [PackageCaskSignature],
        installedReceipts: Set<String>,
        packageFileLists: [String: String],
        availableAppNames: Set<String>
    ) -> [String: ExternalPackageInstallation] {
        var candidates = signatures.compactMap {
            candidate(
                for: $0,
                installedReceipts: installedReceipts,
                packageFileLists: packageFileLists,
                availableAppNames: availableAppNames
            )
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

    private func candidate(
        for signature: PackageCaskSignature,
        installedReceipts: Set<String>,
        packageFileLists: [String: String],
        availableAppNames: Set<String>
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
                matches: signature.appNameCandidates
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
            receiptIdentifiers: matchingReceipts,
            appBundleNames: existingApps,
            score: score
        )
    }

    static func payloadAppName(
        _ appName: String,
        matches candidates: [String]
    ) -> Bool {
        let actualTokens = nameTokens(appName)
        let variantTokens: Set = [
            "alpha", "beta", "canary", "dev", "developer", "nightly", "preview", "rc"
        ]
        return candidates.contains { candidate in
            let candidateTokens = nameTokens(candidate)
            guard actualTokens.intersection(variantTokens)
                == candidateTokens.intersection(variantTokens)
            else { return false }
            return actualTokens.isSubset(of: candidateTokens)
                || candidateTokens.isSubset(of: actualTokens)
        }
    }

    static func identifier(_ identifier: String, matches pattern: String) -> Bool {
        guard pattern.contains("*") || pattern.contains("?") else {
            return identifier == pattern
        }
        var expression = NSRegularExpression.escapedPattern(for: pattern)
        expression = expression
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        guard let regex = try? NSRegularExpression(pattern: "^\(expression)$") else {
            return false
        }
        let range = NSRange(identifier.startIndex..., in: identifier)
        return regex.firstMatch(in: identifier, range: range) != nil
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
