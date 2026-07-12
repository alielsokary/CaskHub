//
//  SettingsView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
            PrivacySettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
        }
        .frame(width: 400, height: 280)
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .system
    }

    var body: some View {
        Form {
            Picker("Theme", selection: $selectedTheme) {
                ForEach(AppTheme.allCases) { option in
                    Label(option.rawValue, systemImage: option.iconName)
                        .tag(option.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: selectedTheme) { _, newValue in
            Analytics.themeChanged(newValue)
        }
    }
}

struct PrivacySettingsView: View {
    @AppStorage(Analytics.enabledKey) private var analyticsEnabled = true
    @AppStorage(CrashReporter.enabledKey) private var crashReportingEnabled = true

    var body: some View {
        Form {
            Toggle("Share anonymous usage analytics", isOn: $analyticsEnabled)
            Text("""
            Helps improve CaskHub via TelemetryDeck. No personal data, \
            no tracking across apps — only anonymized usage signals.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            Toggle("Share crash reports", isOn: $crashReportingEnabled)
            Text("""
            Sends crash reports and error diagnostics to Sentry so bugs \
            get found and fixed faster.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: analyticsEnabled) { _, isOn in
            Analytics.refresh()
            if isOn { Analytics.analyticsReEnabled() }
        }
        .onChange(of: crashReportingEnabled) { _, _ in
            CrashReporter.refresh()
        }
    }
}

#Preview {
    SettingsView()
}
