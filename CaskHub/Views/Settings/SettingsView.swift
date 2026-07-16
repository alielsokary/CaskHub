//
//  SettingsView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
            PrivacySettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 460, height: 480)
    }
}

struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            Text("CaskHub")
                .font(.title2.bold())

            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("Made with ❤️ by Ali Elsokary")
                .font(.callout)
                .padding(.top, 4)

            Link("github.com/alielsokary/CaskHub",
                 destination: URL(string: "https://github.com/alielsokary/CaskHub")!)
                .font(.callout)

            Spacer()

            Text("© 2026 Ali Elsokary. All rights reserved.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct GeneralSettingsView: View {
    @Environment(UpdaterService.self) private var updater
    @Environment(ImageCacheService.self) private var imageCache
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var updater = updater
        Form {
            Section("Startup") {
                Toggle("Launch CaskHub at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            }
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
            }
            Section("Storage") {
                LabeledContent("Clear cached app icons") {
                    Button("Clear Cache") { imageCache.clearCache() }
                }
                Text("Removes cached app icons. They re-download the next time each app is shown.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            CrashReporter.capture(error)
            // Reflect the real state — the change didn't take.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

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
            LabeledContent("Analytics:") {
                checkboxRow(
                    "Share anonymous usage analytics",
                    isOn: $analyticsEnabled,
                    description: """
                    Helps improve CaskHub by sending anonymized usage signals \
                    via TelemetryDeck. No personal data is collected and it \
                    cannot be used to identify you.
                    """
                )
            }
            LabeledContent("Crash Report:") {
                checkboxRow(
                    "Share crash reports",
                    isOn: $crashReportingEnabled,
                    description: """
                    Helps improve CaskHub's stability by sending crash reports \
                    and error diagnostics to Sentry so bugs get found and \
                    fixed faster.
                    """
                )
            }
        }
        .formStyle(.columns)
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: analyticsEnabled) { _, isOn in
            Analytics.refresh()
            if isOn { Analytics.analyticsReEnabled() }
        }
        .onChange(of: crashReportingEnabled) { _, _ in
            CrashReporter.refresh()
        }
    }

    /// Checkbox with its explanation underneath, indented to the checkbox title.
    private func checkboxRow(
        _ title: String,
        isOn: Binding<Bool>,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
        }
        .padding(.bottom, 12)
    }
}

#Preview {
    SettingsView()
        .environment(UpdaterService())
        .environment(ImageCacheService())
}
