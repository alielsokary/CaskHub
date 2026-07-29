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
        let presentation = localHomebrew.actionPresentation(for: cask)
        return CaskInfoProjector.makeRows(from: CaskInfoProjectionInput(
            cask: cask,
            category: category,
            downloadSize: downloadSize,
            actionPresentation: presentation,
            externalVersion: localHomebrew.externalAppVersion(for: cask),
            installationDates: localHomebrew.installationDates(for: cask)
        ))
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
