//
//  AdministratorPasswordSettingsSection.swift
//  CaskHub
//
//  Created by Ali Elsokary on 06/11/2026.
//

import SwiftUI

struct AdministratorPasswordSettingsSection: View {
    let model: AdministratorPasswordSettingsModel
    @State private var isPrompting = false
    @State private var password = ""
    @State private var lastResult: AdministratorPasswordSettingsModel.EnableResult?

    var body: some View {
        if model.isAvailable {
            Section {
                Toggle("Authorize with Touch ID", isOn: Binding(
                    get: { model.isEnabled },
                    set: { enabled in
                        if enabled {
                            lastResult = nil
                            isPrompting = true
                        } else {
                            Task { await model.disable() }
                        }
                    }
                ))
                .toggleStyle(.switch)
                .alert("Authorize with Touch ID", isPresented: $isPrompting) {
                    SecureField("Login Password", text: $password)
                    Button("Cancel", role: .cancel) { password = "" }
                    Button("Save") { save() }
                } message: {
                    Text(promptMessage)
                }
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

    private var promptMessage: LocalizedStringKey {
        switch lastResult {
        case .rejected: "The password was not accepted. Try again."
        case .failed: "The password could not be saved in the Keychain."
        case .enabled, nil: "Enter your login password to save it in the Keychain."
        }
    }

    private func save() {
        let typed = password
        password = ""
        Task {
            let result = await model.enable(password: typed)
            lastResult = result
            if result != .enabled { isPrompting = true }
        }
    }
}
