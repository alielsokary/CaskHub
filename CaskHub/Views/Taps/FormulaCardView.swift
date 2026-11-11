//
//  FormulaCardView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import AppKit
import SwiftUI

/// A tap formula: CaskHub shows it and copies its install command, but doesn't manage it.
struct FormulaCardView: View {
    let formula: TapFormula
    @Environment(\.catalogTextScale) private var textScale

    private var typography: CHType.Catalog { CHType.Catalog(scale: textScale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                TerminalTile(size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: formula.name)
                        .font(typography.title)
                        .foregroundStyle(Color.chTextTitle)
                        .lineLimit(2)
                    Text("Formula")
                        .font(typography.tag)
                        .foregroundStyle(Color.chTextBrand)
                }
                .padding(.top, CHSize.titleInsetBelowIcon * textScale)
            }
            .frame(height: 48 * textScale, alignment: .top)
            Text(verbatim: formula.desc ?? " ")
                .font(typography.description)
                .foregroundStyle(Color.chTextBody)
                .lineLimit(2)
                .frame(minHeight: 30 * textScale, alignment: .top)
            Text(verbatim: formula.version.isEmpty ? " " : "v\(formula.version)")
                .font(typography.meta)
                .foregroundStyle(Color.chTextMuted)
            Spacer(minLength: 2)
            CopyInstallCommandButton(formula: formula, fullWidth: true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity)
        .frame(height: CHSize.cardHeight * textScale, alignment: .topLeading)
        .glassPanel(radius: CHRadius.card)
    }
}

struct FormulaRowView: View {
    let formula: TapFormula
    @Environment(\.catalogTextScale) private var textScale

    private var typography: CHType.Catalog { CHType.Catalog(scale: textScale) }

    var body: some View {
        HStack(spacing: 12) {
            TerminalTile(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: formula.name)
                    .font(typography.title)
                    .foregroundStyle(Color.chTextTitle)
                    .lineLimit(1)
                if let desc = formula.desc {
                    Text(verbatim: desc)
                        .font(typography.description)
                        .foregroundStyle(Color.chTextBody)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("Formula")
                .font(typography.tag)
                .foregroundStyle(Color.chTextBrand)
            CopyInstallCommandButton(formula: formula, fullWidth: false)
                .frame(width: CHSize.listActionWidth, alignment: .trailing)
            Color.clear.frame(width: 24)
        }
        .padding(.vertical, 4)
    }
}

private struct CopyInstallCommandButton: View {
    let formula: TapFormula
    let fullWidth: Bool
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(formula.installCommand, forType: .string)
            copied = true
        } label: {
            ActionCapsule(
                background: .chSurfaceField, border: .chHairlineStrong, foreground: .chTextNav, fullWidth: fullWidth
            ) {
                Label(
                    copied ? String(localized: "Copied") : String(localized: "Copy Command"),
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: formula.installCommand))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
