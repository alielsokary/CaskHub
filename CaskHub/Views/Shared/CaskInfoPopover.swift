//
//  CaskInfoPopover.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/04/2026.
//

import SwiftUI

struct CaskInfoPopover: View {
    let cask: Cask
    let downloadMetadataProvider: any DownloadMetadataProviding

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @State private var downloadSize: DownloadSizeResult?

    init(
        cask: Cask,
        downloadMetadataProvider: any DownloadMetadataProviding =
            DownloadMetadataProvider.shared
    ) {
        self.cask = cask
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

    private var rows: [InfoRow] {
        var result: [InfoRow] = []

        result.append(InfoRow(property: "Token", value: cask.token))

        if let fullToken = cask.fullToken {
            result.append(InfoRow(property: "Full Token", value: fullToken))
        }

        if let tap = cask.tap {
            result.append(InfoRow(property: "Tap", value: tap))
        }

        result.append(InfoRow(
            property: "Homepage",
            value: cask.homepage,
            link: URL(string: cask.homepage)
        ))

        if let url = cask.url {
            result.append(InfoRow(
                property: "URL",
                value: url,
                link: URL(string: url)
            ))
            let sizeValue: String
            switch downloadSize {
            case let .known(bytes): sizeValue = bytes.formatted(.byteCount(style: .file))
            case .unknown: sizeValue = "Unknown"
            case nil: sizeValue = "Loading…"
            }
            result.append(InfoRow(property: "Download Size", value: sizeValue))
        }

        let presentation = localHomebrew.actionPresentation(for: cask)
        let localInstallation = presentation.homebrewInstallation
        let installationSource = presentation.localState.installationSource

        let installedValue: String
        if let version = localInstallation?.installedVersion {
            installedValue = version
        } else if let external = localHomebrew.externalAppVersion(for: cask) {
            installedValue = external
        } else if installationSource != nil {
            installedValue = "Installed"
        } else {
            installedValue = "Not installed"
        }
        result.append(InfoRow(property: "Installed Version", value: installedValue))
        if let installationSource {
            result.append(InfoRow(property: "Installed Via", value: installationSource.rawValue))
        }

        if let bundleVersion = cask.bundleVersion {
            result.append(InfoRow(property: "Bundle Version", value: bundleVersion))
        }

        if let installedAt = localInstallation?.installedAt {
            result.append(InfoRow(
                property: "Installation Date",
                value: installedAt.formatted(date: .abbreviated, time: .shortened)
            ))
        }

        if let bundleShortVersion = cask.bundleShortVersion {
            result.append(InfoRow(property: "Bundle Short Version", value: bundleShortVersion))
        }

        result.append(InfoRow(
            property: "Auto Updates",
            value: cask.autoUpdates.map { $0 ? "Yes" : "No" } ?? "Unknown"
        ))

        result.append(InfoRow(property: "Outdated", value: cask.outdated ? "Yes" : "No"))
        result.append(InfoRow(property: "Deprecated", value: cask.deprecated ? "Yes" : "No"))
        result.append(InfoRow(property: "Disabled", value: cask.disabled ? "Yes" : "No"))

        return result
    }
}

private struct InfoRow {
    let property: String
    let value: String
    var link: URL?
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
        downloadMetadataProvider: UnavailableDownloadMetadataProvider()
    )
    .environment(LocalHomebrewService())
}
