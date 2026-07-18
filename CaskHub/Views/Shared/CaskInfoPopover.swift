//
//  CaskInfoPopover.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/04/2026.
//

import SwiftUI

struct CaskInfoPopover: View {
    let cask: Cask

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @State private var downloadSize: DownloadSizeCache.Result?

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
            downloadSize = await DownloadSizeCache.fetch(urlString: cask.url)
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

        let localInstallation = localHomebrew.installedCasks[cask.token]

        result.append(InfoRow(
            property: "Installed Version",
            value: localInstallation?.installedVersion ?? "Not installed"
        ))

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

/// ponytail: uses the API's default `url`; per-arch `variations` can differ.
@MainActor
enum DownloadSizeCache {
    enum Result {
        case known(Int64)
        case unknown
    }

    private static var cache: [String: Result] = [:]

    static func fetch(urlString: String?) async -> Result {
        guard let urlString, let url = URL(string: urlString) else { return .unknown }
        if let cached = cache[urlString] { return cached }

        let result: Result
        if let bytes = await contentLength(of: url) {
            result = .known(bytes)
        } else {
            result = .unknown
        }
        cache[urlString] = result
        return result
    }

    private static func contentLength(of url: URL) async -> Int64? {
        var head = URLRequest(url: url, timeoutInterval: 15)
        head.httpMethod = "HEAD"
        if let response = try? await URLSession.shared.data(for: head).1,
           response.expectedContentLength > 0 {
            return response.expectedContentLength
        }

        var ranged = URLRequest(url: url, timeoutInterval: 15)
        ranged.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        guard let response = try? await URLSession.shared.data(for: ranged).1 as? HTTPURLResponse,
              let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
              let total = contentRange.split(separator: "/").last.flatMap({ Int64($0) })
        else { return nil }
        return total
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
        )
    )
    .environment(LocalHomebrewService())
}
