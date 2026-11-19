//
//  SaveCaskButton.swift
//  CaskHub
//
//  Created by therustyrobot on 19/11/2026.
//

import SwiftUI

/// Bookmark toggle that adds a cask to, or removes it from, the Saved library page.
struct SaveCaskButton: View {
    let cask: Cask

    @Environment(LocalHomebrewService.self) private var localHomebrew

    private var isSaved: Bool {
        localHomebrew.savedReferences.contains(cask.reference)
    }

    private var label: LocalizedStringKey {
        isSaved ? "Remove from Saved" : "Save"
    }

    var body: some View {
        Button {
            localHomebrew.setSaved(cask.reference, !isSaved)
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.body)
                .foregroundStyle(isSaved ? Color.chTextBrand : Color.chTextMuted)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
