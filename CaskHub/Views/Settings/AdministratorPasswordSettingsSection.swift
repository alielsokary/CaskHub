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
                Button("Forget Saved Password") {
                    Task { await model.forget() }
                }
                .disabled(!model.hasSavedPassword)
            } header: {
                Text("Touch ID")
            } footer: {
                Text("""
                    CaskHub asks for Touch ID instead of your password when an installer needs administrator access. \
                    Turn it on from the password prompt.
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
