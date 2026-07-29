//
//  CaskInfoPopover.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/04/2026.
//

import SwiftUI

struct CaskInfoPopover: View {
    let cask: Cask
    let category: CaskCategoryPresentation?
    let downloadMetadataProvider: any DownloadMetadataProviding

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @State private var downloadSize: DownloadSizeResult?

    init(
        cask: Cask,
        category: CaskCategoryPresentation? = nil,
        downloadMetadataProvider: any DownloadMetadataProviding =
            DownloadMetadataProvider.shared
    ) {
        self.cask = cask
        self.category = category
        self.downloadMetadataProvider = downloadMetadataProvider
    }

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 8) {
            headerRow
            Divider()
            ForEach(rows, id: \.property) { row in
                GridRow {
                    Text(row.property)
                        .font(CHType.body)
                        .foregroundStyle(Color.chTextBody)
                        .gridColumnAlignment(.leading)
                    if let link = row.link {
                        Link(row.value, destination: link)
                            .font(CHType.statusMono)
                            .foregroundStyle(Color.chTextBrand)
                            .gridColumnAlignment(.leading)
                    } else {
                        Text(row.value)
                            .font(CHType.statusMono)
                            .foregroundStyle(Color.chTextTitle)
                            .textSelection(.enabled)
                            .gridColumnAlignment(.leading)
                    }
                }
                Divider()
            }
        }
        .padding()
        .frame(minWidth: 400)
        .task(id: cask.token) {
            downloadSize = await downloadMetadataProvider.downloadSize(for: cask.url)
        }
    }

    private var headerRow: some View {
        GridRow {
            Text("Property")
                .font(CHType.cardTitle)
                .foregroundStyle(Color.chTextTitle)
            Text("Value")
                .font(CHType.cardTitle)
                .foregroundStyle(Color.chTextTitle)
        }
    }

    private var rows: [CaskInfoRow] {
        makeRows(localHomebrew: localHomebrew, downloadSize: downloadSize)
    }

    func makeRows(
        localHomebrew: LocalHomebrewService,
        downloadSize: DownloadSizeResult?
    ) -> [CaskInfoRow] {
        let presentation = localHomebrew.actionPresentation(for: cask)
        return CaskInfoRowProjection.make(CaskInfoProjectionInput(
            cask: cask,
            category: category,
            downloadSize: downloadSize,
            actionPresentation: presentation,
            externalVersion: localHomebrew.externalAppVersion(for: cask),
            installationDates: localHomebrew.installationDates(for: cask)
        ))
    }
}

struct CaskInfoRow {
    let property: String
    let value: String
    var link: URL?
}

private struct CaskInfoProjectionInput {
    let cask: Cask
    let category: CaskCategoryPresentation?
    let downloadSize: DownloadSizeResult?
    let actionPresentation: CaskActionPresentation
    let externalVersion: String?
    let installationDates: CaskInstallationDates?
}

private enum CaskInfoRowProjection {
    static func make(_ input: CaskInfoProjectionInput) -> [CaskInfoRow] {
        identityRows(for: input.cask)
            + downloadRows(for: input.cask, size: input.downloadSize)
            + installationRows(
                presentation: input.actionPresentation,
                externalVersion: input.externalVersion,
                dates: input.installationDates
            )
            + metadataRows(for: input.cask, category: input.category)
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
            property: "Homepage",
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
        return [
            CaskInfoRow(property: "URL", value: url, link: URL(string: url)),
            CaskInfoRow(property: "Download Size", value: downloadSizeValue(size))
        ]
    }

    private static func installationRows(
        presentation: CaskActionPresentation,
        externalVersion: String?,
        dates: CaskInstallationDates?
    ) -> [CaskInfoRow] {
        var rows = [
            CaskInfoRow(
                property: "Installed Version",
                value: installedVersion(
                    presentation: presentation,
                    externalVersion: externalVersion
                )
            )
        ]
        if let source = presentation.localState.installationSource {
            rows.append(CaskInfoRow(property: "Installed Via", value: source.rawValue))
        }
        if let installedAt = dates?.installedAt {
            rows.append(CaskInfoRow(
                property: "Installed",
                value: formatted(installedAt)
            ))
        }
        if let lastUpdatedAt = dates?.lastUpdatedAt {
            rows.append(CaskInfoRow(
                property: "Last Updated",
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
            rows.append(CaskInfoRow(property: "Bundle Version", value: bundleVersion))
        }
        if let shortVersion = cask.bundleShortVersion {
            rows.append(CaskInfoRow(property: "Bundle Short Version", value: shortVersion))
        }
        rows.append(CaskInfoRow(
            property: "Main Category",
            value: category?.mainName ?? "Uncategorized"
        ))
        rows.append(CaskInfoRow(
            property: "Subcategories",
            value: category?.subcategoryNames.joined(separator: ", ").nilIfEmpty ?? "None"
        ))
        rows.append(CaskInfoRow(
            property: "Auto Updates",
            value: cask.autoUpdates.map { $0 ? "Yes" : "No" } ?? "Unknown"
        ))
        return rows
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
            ? "Not installed"
            : "Installed"
    }

    private static func downloadSizeValue(_ size: DownloadSizeResult?) -> String {
        switch size {
        case let .known(bytes): bytes.formatted(.byteCount(style: .file))
        case .unknown: "Unknown"
        case nil: "Loading…"
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

#Preview {
    CaskInfoPopover(
        cask: Cask(
            token: "1password",
            fullToken: "1password",
            tap: "homebrew/cask",
            name: ["1Password"],
            desc: "Password manager",
            homepage: "https://1password.com/",
            url: "https://downloads.1password.com/mac/1Password-8.12.10-aarch64.zip",
            version: "8.12.10",
            bundleVersion: nil,
            bundleShortVersion: nil,
            outdated: false,
            deprecated: false,
            disabled: false,
            autoUpdates: true
        ),
        category: CaskCategoryPresentation(
            mainID: "securityPrivacy",
            mainName: "Security & Privacy",
            subcategoryNames: ["Productivity"]
        ),
        downloadMetadataProvider: UnavailableDownloadMetadataProvider()
    )
    .environment(LocalHomebrewService())
}
