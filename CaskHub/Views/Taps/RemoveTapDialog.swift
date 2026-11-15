//
//  RemoveTapDialog.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import SwiftUI

struct RemoveTapDialog: View {
    let viewModel: CaskCatalogViewModel
    let tapName: String
    @State var preview: TapRemovalPreview?
    @State private var isRemoving = false
    @State private var failure: String?

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @Environment(\.dismiss) private var dismiss

    static func message(for preview: TapRemovalPreview) -> String {
        preview.removesInstalledItems
            ? String(localized: "This uninstalls everything installed from this tap:")
            : String(localized: "CaskHub stops showing apps from this tap.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: String(localized: "Remove \(tapName)?"))
                .font(CHType.section)
                .foregroundStyle(Color.chTextTitle)
            if let preview {
                Text(verbatim: failure ?? Self.message(for: preview))
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextBody)
                if preview.removesInstalledItems, failure == nil {
                    itemList(preview)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            HStack(spacing: 8) {
                Spacer()
                TapSheetPill.neutral(String(localized: "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isRemoving)
                TapSheetPill.primary(String(localized: "Remove Tap"), action: remove)
                    .disabled(preview == nil || isRemoving)
                    .opacity(preview == nil || isRemoving ? 0.45 : 1)
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(width: 440)
        .background(Color.chSurfaceHero)
        .interactiveDismissDisabled(isRemoving)
        .task {
            if preview == nil { preview = await viewModel.removalPreview(for: tapName) }
        }
    }

    private func itemList(_ preview: TapRemovalPreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(preview.installedCasks) { cask in
                row(name: cask.displayName, detail: cask.token)
            }
            ForEach(preview.installedFormulae, id: \.self) { formula in
                row(name: CaskReference.bareToken(formula), detail: String(localized: "formula"))
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.chSurfaceWell))
    }

    private func row(name: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: name)
                .font(CHType.bodySm)
                .foregroundStyle(Color.chTextTitle)
            Text(verbatim: detail)
                .font(CHType.statusMono)
                .foregroundStyle(Color.chTextMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func remove() {
        guard let preview else { return }
        isRemoving = true
        Task {
            do {
                try await viewModel.removeTap(preview)
                dismiss()
            } catch {
                let token = LocalHomebrewService.tapOperationToken(tapName)
                if case let .failure(operationFailure) = localHomebrew.actionAlert(for: token) {
                    failure = operationFailure.message
                    localHomebrew.send(.dismissFailure(token: token))
                } else {
                    failure = error.localizedDescription
                }
            }
            isRemoving = false
        }
    }
}
