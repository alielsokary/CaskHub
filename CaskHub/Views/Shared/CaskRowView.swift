//
//  CaskRowView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import SwiftUI

struct CaskRowView: View {
    let cask: Cask
    var downloads: String?

    var body: some View {
        HStack(spacing: 12) {
            CaskIconView(size: 40)
            appInfo
            Spacer()
            metadata
            installButton
        }
        .padding(.vertical, 4)
    }

    // MARK: - App Info

    private var appInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cask.displayName)
                .font(.headline)
                .lineLimit(1)
            if let desc = cask.desc {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    // MARK: - Metadata

    private var metadata: some View {
        HStack(spacing: 12) {
            if let downloads {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.to.line")
                    Text(downloads)
                }
            }
            HStack(spacing: 3) {
                Image(systemName: "tag")
                Text("v\(cask.displayVersion)")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    // MARK: - Install Button

    private var installButton: some View {
        Button {
            // Install action — wired up in Phase 5
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.to.line")
                    .font(.caption2)
                Text("Install")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    List {
        CaskRowView(
            cask: Cask(
                token: "firefox",
                name: ["Firefox"],
                desc: "Web browser developed by Mozilla Foundation",
                homepage: "https://www.mozilla.org/firefox/",
                version: "125.0",
                installed: nil,
                outdated: false,
                deprecated: false,
                disabled: false,
                autoUpdates: true
            ),
            downloads: "1.2M"
        )
    }
    .frame(width: 600)
}
