//
//  UpdateSettingsView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 02/08/2026.
//

import SwiftUI

struct UpdateSettingsView: View {
    @Environment(UpdaterService.self) private var updater

    var body: some View {
        @Bindable var updater = updater
        Form {
            Section("Automatic Updates") {
                Toggle(
                    "Automatically check for updates",
                    isOn: $updater.automaticallyChecksForUpdates
                )

                Text(String(
                    localized: "settings.updates.automaticChecks",
                    defaultValue: """
                    When automatic checks are enabled, CaskHub downloads updates in the \
                    background and always shows the update prompt before installation.
                    """,
                    comment: "Settings footnote for the automatic update checks toggle"
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text(lastCheckDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if updater.isCheckingForUpdates {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityHidden(true)

                            Text("Checking…")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Checking for updates")
                    } else {
                        Button("Check Now") {
                            updater.checkForUpdates()
                        }
                        .disabled(!updater.canCheckForUpdates)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var lastCheckDescription: String {
        guard let date = updater.lastUpdateCheckDate else {
            return "Last checked: Never"
        }
        return "Last checked: \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}
