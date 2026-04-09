//
//  CaskInfoPopover.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/04/2026.
//

import SwiftUI

struct CaskInfoPopover: View {
    let cask: Cask

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 8) {
            headerRow
            Divider()
            ForEach(rows, id: \.property) { row in
                GridRow {
                    Text(row.property)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                    if let link = row.link {
                        Link(row.value, destination: link)
                            .gridColumnAlignment(.leading)
                    } else {
                        Text(row.value)
                            .textSelection(.enabled)
                            .gridColumnAlignment(.leading)
                    }
                }
                Divider()
            }
        }
        .font(.callout)
        .padding()
        .frame(minWidth: 400)
    }

    private var headerRow: some View {
        GridRow {
            Text("Property")
                .fontWeight(.semibold)
            Text("Value")
                .fontWeight(.semibold)
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
        }

        result.append(InfoRow(
            property: "Installed Version",
            value: cask.installed ?? "Not installed"
        ))

        if let bundleVersion = cask.bundleVersion {
            result.append(InfoRow(property: "Bundle Version", value: bundleVersion))
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
    var link: URL? = nil
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
            installed: nil,
            bundleVersion: nil,
            bundleShortVersion: nil,
            outdated: false,
            deprecated: false,
            disabled: false,
            autoUpdates: true
        )
    )
}
