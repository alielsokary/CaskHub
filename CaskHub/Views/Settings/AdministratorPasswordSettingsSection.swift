//
//  AdministratorPasswordSettingsSection.swift
//  CaskHub
//
//  Created by Ali Elsokary on 06/11/2026.
//

import SwiftUI

struct AdministratorPasswordSettingsSection: View {
    let model: AdministratorPasswordSettingsModel

    var body: some View {
        if model.isAvailable {
            Section {
                Toggle("Authorize with Touch ID", isOn: Binding(
                    get: { model.isEnabled },
                    set: { enabled in Task { await model.setEnabled(enabled) } }
                ))
                .toggleStyle(.switch)
            } header: {
                Text("Touch ID")
            } footer: {
                Text("""
                    Use your fingerprint instead of your password when Homebrew needs administrator access. \
                    Turning this off removes the saved password.
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
