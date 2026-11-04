//
//  ApplicationDirectorySettingsRow.swift
//  CaskHub
//
//  Created by Ali Elsokary on 03/11/2026.
//

import AppKit
import SwiftUI

struct ApplicationDirectorySettingsRow: View {
    let localHomebrew: LocalHomebrewService
    @State private var model: ApplicationDirectorySettingsModel
    @FocusState private var isFieldFocused: Bool

    init(localHomebrew: LocalHomebrewService) {
        self.localHomebrew = localHomebrew
        _model = State(initialValue: ApplicationDirectorySettingsModel(settings: localHomebrew))
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            Text("Application Directory")
            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $model.field,
                    prompt: Text(verbatim: LocalHomebrewService.defaultApplicationDirectoryPath)
                )
                .labelsHidden()
                .accessibilityLabel("Application Directory")
                .font(.body.monospaced())
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
                .focused($isFieldFocused)
                .onSubmit { Task { await model.applyTypedPath() } }
                .onChange(of: model.field) { model.validate() }
                .onChange(of: isFieldFocused) { _, focused in
                    if !focused { Task { await model.applyOnFocusLoss() } }
                }

                Button("Choose…") { chooseDirectory() }
                    .fixedSize()
                if model.isOverridden {
                    Button("Use Default") { Task { await model.reset() } }
                        .fixedSize()
                }
            }
            if model.isInvalid {
                Label("Folder not found", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            Text("New installs land here. Apps already installed stay where they are.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: localHomebrew.applicationDirectoryOverride) { model.synchronize() }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = localHomebrew.applicationDirectoryOverride
            ?? URL(fileURLWithPath: LocalHomebrewService.defaultApplicationDirectoryPath)
        panel.message = String(localized: "Select the folder where new apps install")
        let response = CrashReporter.withHangTrackingPaused { panel.runModal() }
        guard response == .OK, let url = panel.url else { return }
        Task { await model.applySelection(url) }
    }
}
