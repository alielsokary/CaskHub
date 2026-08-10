//
//  CaskMetadataProjector.swift
//  CaskHub
//
//  Created by Ali Elsokary on 29/07/2026.
//

import Foundation

struct CaskCategoryPresentation: Equatable {
    let mainID: CategoryID
    let mainName: String
    let subcategoryNames: [String]
}

enum CaskCategoryProjector {
    static func make(
        token: String,
        mappings: [String: TokenCategoryMapping],
        definitions: [CategoryID: CategoryDefinition]
    ) -> CaskCategoryPresentation? {
        guard let mapping = mappings[token] else { return nil }
        return CaskCategoryPresentation(
            mainID: mapping.primary,
            mainName: displayName(for: mapping.primary, definitions: definitions),
            subcategoryNames: mapping.secondary.map {
                displayName(for: $0, definitions: definitions)
            }
        )
    }

    private static func displayName(
        for categoryID: CategoryID,
        definitions: [CategoryID: CategoryDefinition]
    ) -> String {
        guard let definition = definitions[categoryID] else { return categoryID }
        return localizedCategoryName(categoryID, fallback: definition.displayName)
    }
}

struct CaskInfoRow: Equatable {
    let property: String
    let value: String
    var link: URL?
}

struct CaskInfoProjectionInput {
    let cask: Cask
    let category: CaskCategoryPresentation?
    let downloadSize: DownloadSizeResult?
    let actionPresentation: CaskActionPresentation
    let externalVersion: String?
    let installationDates: CaskInstallationDates?
}

enum CaskInfoProjector {
    static func makeRows(from input: CaskInfoProjectionInput) -> [CaskInfoRow] {
        identityRows(for: input.cask)
            + downloadRows(for: input.cask, size: input.downloadSize)
            + installationRows(
                presentation: input.actionPresentation,
                externalVersion: input.externalVersion,
                dates: input.installationDates
            )
            + metadataRows(for: input.cask, category: input.category)
            + statusRows(for: input.cask)
    }

    private static func identityRows(for cask: Cask) -> [CaskInfoRow] {
        var rows = [CaskInfoRow(property: "Token", value: cask.token)]
        if let fullToken = cask.fullToken {
            rows.append(CaskInfoRow(property: "Full Token", value: fullToken))
        }
        if let tap = cask.tap {
            rows.append(CaskInfoRow(property: "Tap", value: tap))
        }
        rows.append(CaskInfoRow(
            property: String(localized: "Homepage"),
            value: cask.homepage,
            link: URL(string: cask.homepage)
        ))
        return rows
    }

    private static func downloadRows(
        for cask: Cask,
        size: DownloadSizeResult?
    ) -> [CaskInfoRow] {
        guard let url = cask.url else { return [] }
        var rows = [CaskInfoRow(property: "URL", value: url, link: URL(string: url))]
        if let sha256 = cask.sha256 {
            rows.append(CaskInfoRow(
                property: "SHA",
                value: sha256 == "no_check"
                    ? String(localized: "sha256 :no_check (rolling download URL)")
                    : sha256
            ))
        }
        rows.append(CaskInfoRow(
            property: String(localized: "Download Size"),
            value: downloadSizeValue(size)
        ))
        return rows
    }

    private static func installationRows(
        presentation: CaskActionPresentation,
        externalVersion: String?,
        dates: CaskInstallationDates?
    ) -> [CaskInfoRow] {
        var rows = [
            CaskInfoRow(
                property: String(localized: "Installed Version"),
                value: installedVersion(
                    presentation: presentation,
                    externalVersion: externalVersion
                )
            )
        ]
        if let source = presentation.localState.installationSource {
            rows.append(CaskInfoRow(
                property: String(localized: "Installed Via"),
                value: source.title
            ))
        }
        guard let dates else { return rows }

        let labels = dateLabels(for: dates.basis)
        if let installedAt = dates.installedAt {
            rows.append(CaskInfoRow(
                property: labels.installed,
                value: formatted(installedAt)
            ))
        }
        if let lastUpdatedAt = dates.lastUpdatedAt {
            rows.append(CaskInfoRow(
                property: labels.updated,
                value: formatted(lastUpdatedAt)
            ))
        }
        return rows
    }

    private static func metadataRows(
        for cask: Cask,
        category: CaskCategoryPresentation?
    ) -> [CaskInfoRow] {
        var rows: [CaskInfoRow] = []
        if let bundleVersion = cask.bundleVersion {
            rows.append(CaskInfoRow(
                property: String(localized: "Bundle Version"),
                value: bundleVersion
            ))
        }
        if let shortVersion = cask.bundleShortVersion {
            rows.append(CaskInfoRow(
                property: String(localized: "Bundle Short Version"),
                value: shortVersion
            ))
        }
        rows.append(CaskInfoRow(
            property: String(localized: "Main Category"),
            value: category?.mainName ?? String(localized: "Uncategorized")
        ))
        rows.append(CaskInfoRow(
            property: String(localized: "Subcategories"),
            value: category?.subcategoryNames.joined(separator: ", ").nilIfEmpty
                ?? String(localized: "None")
        ))
        rows.append(CaskInfoRow(
            property: String(localized: "Auto Updates"),
            value: cask.autoUpdates.map(yesNo) ?? String(localized: "Unknown")
        ))
        return rows
    }

    private static func statusRows(for cask: Cask) -> [CaskInfoRow] {
        [
            CaskInfoRow(property: String(localized: "Outdated"), value: yesNo(cask.outdated)),
            CaskInfoRow(property: String(localized: "Deprecated"), value: yesNo(cask.deprecated)),
            CaskInfoRow(property: String(localized: "Disabled"), value: yesNo(cask.disabled))
        ]
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }

    private static func installedVersion(
        presentation: CaskActionPresentation,
        externalVersion: String?
    ) -> String {
        if let version = presentation.homebrewInstallation?.installedVersion {
            return version
        }
        if let externalVersion {
            return externalVersion
        }
        return presentation.localState.installationSource == nil
            ? String(localized: "Not installed")
            : String(localized: .caskStateInstalled)
    }

    private static func downloadSizeValue(_ size: DownloadSizeResult?) -> String {
        switch size {
        case let .known(bytes): bytes.formatted(.byteCount(style: .file))
        case .unknown: String(localized: "Unknown")
        case nil: String(localized: "Loading…")
        }
    }

    private static func dateLabels(
        for basis: CaskInstallationDateBasis
    ) -> (installed: String, updated: String) {
        switch basis {
        case .homebrewMetadata:
            return (
                String(localized: .caskDateLabelInstalled),
                String(localized: "Last Updated")
            )
        case .applicationBundleAttributes:
            return (
                String(localized: "Bundle Created"),
                String(localized: "Bundle Modified")
            )
        }
    }

    private static func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
