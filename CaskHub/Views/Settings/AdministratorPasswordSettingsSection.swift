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
                    set: { enabled in Task { enabled ? await turnOn() : await model.disable() } }
                ))
                .toggleStyle(.switch)
            } header: {
                Text("Touch ID")
            } footer: {
                Text("""
                    Use your fingerprint instead of your password when Homebrew needs administrator access. \
                    Your password is saved in the Keychain and removed when you turn this off.
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func turnOn() async {
        var message = String(localized: "Enter your login password to save it in the Keychain.")
        while let response = AdministratorPasswordDialog.present(
            message: message, offerRemember: false, rememberChecked: false
        ) {
            switch await model.enable(password: response.password) {
            case .enabled: return
            case .rejected: message = String(localized: "The password was not accepted. Try again.")
            case .failed: message = String(localized: "The password could not be saved in the Keychain.")
            }
        }
    }
}
