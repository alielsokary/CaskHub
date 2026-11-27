//
//  CategoryService.swift
//  CaskHub
//
//  Created by Ali Elsokary on 27/03/2026.
//

import Foundation
import Observation

typealias CategoryID = String

/// Falls back to the pipeline's English name when the catalog has no
/// `category.<id>` entry yet (e.g. a new category shipped via data sync).
nonisolated func localizedCategoryName(_ id: CategoryID, fallback: String) -> String {
    Bundle.main.localizedString(forKey: "category.\(id)", value: fallback, table: nil)
}

nonisolated struct CategoryDefinition: Codable, Hashable {
    let displayName: String
    let icon: String
}

nonisolated struct TokenCategoryMapping: Codable, Hashable {
    let primary: CategoryID
    let secondary: [CategoryID]
}

nonisolated struct CaskAppIdentity: Decodable, Hashable, Sendable {
    let bundleName: String
    let bundleIdentifier: String
    // Absent for direct apps and legacy metadata. Both are required to extend
    // a package cask's declared name candidates with verified payload evidence.
    var packageIdentifier: String?
    var installedPath: String?

    func verifiesPackageApp(for cask: Cask) -> Bool {
        guard cask.hasPackageArtifact, let packageIdentifier,
              bundleName.hasSuffix(".app"), !bundleName.contains("/"),
              installedPath == "/Applications/\(bundleName)"
        else { return false }
        return cask.packageIdentifiers.contains { fnmatch($0, packageIdentifier, 0) == 0 }
    }
}

nonisolated struct HousePick: Decodable, Hashable {
    let token: String
}

nonisolated struct CaskCategoryData: Decodable {
    let version: Int
    let generatedDate: String
    let releaseTag: String?
    let categories: [String: CategoryDefinition]
    let tokenToCategory: [String: TokenCategoryMapping]
    /// Manifest of tokens with an icon on the CaskFlow icons branch, stamped
    /// into the release asset. Absent in pre-2026.07 data → nil.
    let iconTokens: [String]?
    var cliTokens: [String]?
    // Optional for releases predating app identity metadata.
    var appIdentities: [String: [CaskAppIdentity]]?
    var packageAppCandidates: [String: [PackageApplicationIdentity]]?
    var packageProductIdentities: [String: [PackageApplicationIdentity]]?
    var metadataUpdatedAt: String?
    var housePick: HousePick?
}

@MainActor
@Observable
final class CategoryService {
    private(set) var categoryDefinitions: [CategoryID: CategoryDefinition] = [:]
    private(set) var tokenMappings: [String: TokenCategoryMapping] = [:]
    private(set) var version: Int = 0
    private(set) var generatedDate: String = ""
    private(set) var releaseTag: String?
    private(set) var iconTokens: Set<String>?
    private(set) var cliTokens: Set<String> = []
    private(set) var appIdentities: [String: [CaskAppIdentity]] = [:]
    private(set) var packageAppCandidates: [String: [PackageApplicationIdentity]] = [:]
    private(set) var packageProductIdentities: [String: [PackageApplicationIdentity]] = [:]
    private(set) var metadataUpdatedAt: String?
    private(set) var housePick: HousePick?
    private(set) var catalogStateRevision = 0

    var orderedCategories: [(id: CategoryID, definition: CategoryDefinition)] {
        categoryDefinitions
            .sorted { lhs, rhs in
                if lhs.key == "other" { return false }
                if rhs.key == "other" { return true }
                let lhsName = localizedCategoryName(lhs.key, fallback: lhs.value.displayName)
                let rhsName = localizedCategoryName(rhs.key, fallback: rhs.value.displayName)
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
            .map { (id: $0.key, definition: $0.value) }
    }

    /// Off-main decode; never overwrites fresher remote data.
    func loadBundledCategoriesAsync() async {
        guard version == 0 else { return }
        guard let catalog = await Self.decodeBundledCategories(), version == 0
        else { return }
        applyData(catalog)
    }

    @concurrent private static func decodeBundledCategories() async -> CaskCategoryData? {
        guard let url = Bundle.main.url(forResource: "categories", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(CaskCategoryData.self, from: data)
    }

    func refreshFromRemote() async {
        await loadBundledCategoriesAsync()
        guard let remote = await CaskFlowReleases.fetch(CaskCategoryData.self, asset: "categories.json") else { return }
        applyRemoteData(remote)
    }

    func applyRemoteData(_ remote: CaskCategoryData) {
        guard remote.version == version, remote.generatedDate >= generatedDate,
              remote.generatedDate > generatedDate
                || (remote.metadataUpdatedAt ?? "") > (metadataUpdatedAt ?? "") else { return }
        applyData(remote)
    }

    func addingAppIdentities(to casks: [Cask]) -> [Cask] {
        casks.map { cask in
            var enriched = cask
            enriched.catalogIsCLI = cliTokens.contains(cask.token)
            let identities = (appIdentities[cask.token] ?? []).filter {
                $0.bundleIdentifier.range(
                    of: Self.bundleIdentifierPattern, options: .regularExpression
                ) != nil
            }
            enriched.catalogPackageAppIdentifiers = Dictionary(
                grouping: identities.filter { $0.verifiesPackageApp(for: cask) },
                by: \.bundleName
            ).mapValues { $0.map(\.bundleIdentifier) }
            let names = Set((enriched.appArtifactNames + enriched.packageAppNameCandidates).map { $0.lowercased() })
            enriched.catalogBundleIdentifiers = identities.filter {
                names.contains($0.bundleName.lowercased())
            }.map(\.bundleIdentifier)
            enriched.catalogPackageCandidates = validPackageIdentities(packageAppCandidates[cask.token] ?? [], for: cask)
            enriched.catalogPackageProducts = cask.hasPackageArtifact ? packageProductIdentities[cask.token].map {
                // A reviewed product has one app. Invalid evidence must not reopen legacy fallback.
                $0.count <= 1 ? validPackageIdentities($0, for: cask) : []
            } : nil
            return enriched
        }
    }

    private func validPackageIdentities(_ candidates: [PackageApplicationIdentity], for cask: Cask) -> [PackageApplicationIdentity] {
        candidates.filter { candidate in
            let identity = CaskAppIdentity(
                bundleName: candidate.bundleName, bundleIdentifier: candidate.bundleIdentifier,
                packageIdentifier: candidate.packageIdentifier, installedPath: candidate.installedPath
            )
            return identity.verifiesPackageApp(for: cask)
                && candidate.bundleIdentifier.range(
                    of: Self.bundleIdentifierPattern, options: .regularExpression
                ) != nil
        }
    }

    /// Shipping apps use underscores and single inner spaces (com.mediahuman.YouTube to MP3); matching is exact.
    private static let bundleIdentifierPattern = #"\A[A-Za-z0-9_-]+(?: [A-Za-z0-9_-]+)*(?:\.[A-Za-z0-9_-]+(?: [A-Za-z0-9_-]+)*)*\z"#

    /// Fonts are identified by token, so CaskHub supplies this category itself.
    static let fontsCategoryID: CategoryID = "fonts"

    func applyData(_ catalog: CaskCategoryData) {
        categoryDefinitions = catalog.categories.merging(
            [Self.fontsCategoryID: CategoryDefinition(displayName: "Fonts", icon: "textformat")]
        ) { pipeline, _ in pipeline }
        tokenMappings = catalog.tokenToCategory

        version = catalog.version
        generatedDate = catalog.generatedDate
        releaseTag = catalog.releaseTag
        iconTokens = catalog.iconTokens.map(Set.init)
        cliTokens = Set(catalog.cliTokens ?? [])
        if let identities = catalog.appIdentities { appIdentities = identities }
        // Missing candidate metadata revokes prior conditional evidence.
        packageAppCandidates = catalog.packageAppCandidates ?? [:]
        packageProductIdentities = catalog.packageProductIdentities ?? [:]
        if let updatedAt = catalog.metadataUpdatedAt { metadataUpdatedAt = updatedAt }
        housePick = catalog.housePick
        catalogStateRevision &+= 1
    }

    func category(for token: String) -> CategoryID? {
        tokenMappings[token]?.primary
    }

    // MARK: - Tap casks

    private var tapMappings: [String: TokenCategoryMapping] = [:]
    private var tapAliases: [String: String] = [:]
    private(set) var tapIconRefs: Set<String> = []
    /// Bumped only by tap data, so tap cask icons reload without reloading every official icon.
    private(set) var tapDataRevision = 0

    func refreshTapsFromRemote() async {
        guard let remote = await CaskFlowReleases.fetch(TapCatalogData.self, asset: "tap-categories.json") else { return }
        applyTapData(remote)
    }

    func applyTapData(_ data: TapCatalogData) {
        guard data.version == 1 else { return }
        tapMappings = data.casks
        tapAliases = data.sameAs
        tapIconRefs = Set(data.iconCasks ?? [])
        tapDataRevision &+= 1
        catalogStateRevision &+= 1
    }

    func officialAlias(for reference: String) -> String? {
        tapAliases[reference]
    }

    /// Official token, tap reference, or a tap cask aliased to an official one; unknown category ids are dropped.
    func mapping(for reference: String) -> TokenCategoryMapping? {
        if let official = tokenMappings[reference] { return official }
        if let alias = tapAliases[reference] { return tokenMappings[alias] }
        guard let mapping = tapMappings[reference], categoryDefinitions[mapping.primary] != nil else { return nil }
        return TokenCategoryMapping(
            primary: mapping.primary,
            secondary: mapping.secondary.filter { categoryDefinitions[$0] != nil }
        )
    }

    func displayName(for categoryID: CategoryID) -> String {
        guard let definition = categoryDefinitions[categoryID] else { return categoryID }
        return localizedCategoryName(categoryID, fallback: definition.displayName)
    }
}
