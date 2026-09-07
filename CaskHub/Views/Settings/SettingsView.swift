//
//  SettingsView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import AppKit
import SwiftUI

enum SettingsSection: Hashable {
    case general
    case appearance
    case homebrew
    case privacy
    case updates
    case about
}

struct SettingsView: View {
    @Binding var selection: SettingsSection

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsSection.general)
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(SettingsSection.appearance)
            HomebrewSettingsView()
                .tabItem {
                    Label("Homebrew", systemImage: "shippingbox")
                }
                .tag(SettingsSection.homebrew)
            PrivacySettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
                .tag(SettingsSection.privacy)
            UpdateSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(SettingsSection.updates)
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsSection.about)
        }
        .frame(width: 650, height: 560)
    }
}

struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return String(localized: "Version \(short) (\(build))")
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

            Link("github.com/alielsokary/CaskHub", destination: CaskHubLinks.repository)
                .font(.callout)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Support")
                    .font(.headline)

                GroupBox {
                    HStack(spacing: 12) {
                        Image(systemName: "ladybug")
                            .accessibilityHidden(true)

                        Text("Submit a bug or feature request")

                        Spacer()

                        Link("View", destination: CaskHubLinks.issues)
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)

            Text("© 2026 Ali Elsokary. All rights reserved.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct GeneralSettingsView: View {
    @Environment(LocalHomebrewService.self) private var localHomebrew
    @State private var settingsModel = GeneralSettingsModel()
    @AppStorage(SidebarView.showAdoptKey) private var showAdoptApps = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(
                    "Launch CaskHub at login",
                    isOn: Binding(
                        get: { settingsModel.launchAtLogin },
                        set: { settingsModel.setLaunchAtLogin($0) }
                    )
                )
            }
            Section("Sidebar") {
                Toggle("Show Adopt Apps", isOn: $showAdoptApps)
                Text("Adopt Apps lists installed apps that Homebrew can start managing for you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: Binding(
                    get: { localHomebrew.zapOnUninstall },
                    set: { localHomebrew.setZapOnUninstall($0) }
                )) {
                    Text(.settingsUninstallRemoveAppData)
                }
                Text(.settingsUninstallDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text(.settingsUninstallTitle)
            }
            Section("Permissions") {
                LabeledContent("App Management") {
                    HStack(spacing: 10) {
                        permissionBadge
                        if settingsModel.appManagement != .granted {
                            Button("Open System Settings") {
                                settingsModel.openAppManagementSettings()
                            }
                        }
                    }
                }
                Text(.settingsAppManagementDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await settingsModel.refreshAppManagement() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            // Re-probe when the user comes back from System Settings.
            Task { await settingsModel.refreshAppManagement() }
        }
    }

    @ViewBuilder
    private var permissionBadge: some View {
        switch settingsModel.appManagement {
        case .granted:
            badge("Granted", icon: "checkmark.circle.fill", tint: .green)
        case .denied:
            badge("Not Granted", icon: "xmark.circle.fill", tint: .secondary)
        case .unknown:
            badge("Unknown", icon: "questionmark.circle", tint: .secondary)
        }
    }

    private func badge(_ title: LocalizedStringKey, icon: String, tint: some ShapeStyle) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
        }
        .foregroundStyle(tint)
    }

}

struct HomebrewSettingsView: View {
    @Environment(LocalHomebrewService.self) private var localHomebrew

    var body: some View {
        HomebrewSettingsContent(localHomebrew: localHomebrew)
    }
}

private struct HomebrewSettingsContent: View {
    let localHomebrew: LocalHomebrewService
    @State private var locationModel: HomebrewLocationSettingsModel

    init(localHomebrew: LocalHomebrewService) {
        self.localHomebrew = localHomebrew
        _locationModel = State(initialValue: HomebrewLocationSettingsModel(
            settings: localHomebrew
        ))
    }

    var body: some View {
        @Bindable var locationModel = locationModel
        Form {
            Section("Status") {
                LabeledContent("Homebrew") {
                    if let version = localHomebrew.brewVersion {
                        Label("Installed (\(version))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 10) {
                            Label("Not Found", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Button("Go to brew.sh") {
                                NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
                            }
                        }
                    }
                }
                LabeledContent(
                    "Architecture",
                    value: HomebrewLocator.isAppleSilicon ? "Apple Silicon" : "Intel"
                )
            }
            Section("Paths") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Homebrew Location", selection: $locationModel.selection) {
                        locationOption(.appleSilicon, title: "Apple Silicon Mac")
                            .tag(HomebrewLocationChoice.appleSilicon)
                        locationOption(.intel, title: "Intel Mac")
                            .tag(HomebrewLocationChoice.intel)
                        locationOption(.custom, title: "Custom brew path")
                            .tag(HomebrewLocationChoice.custom)
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                    .onChange(of: locationModel.selection) { _, choice in
                        Task { await locationModel.applyChoice(choice) }
                    }

                    HStack(spacing: 10) {
                        TextField(
                            "",
                            text: $locationModel.customPathField,
                            prompt: Text("Homebrew path")
                        )
                        .labelsHidden()
                        .accessibilityLabel("Custom brew path")
                        .font(.body.monospaced())
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                        .onSubmit {
                            Task { await locationModel.applyTypedPath() }
                        }
                        .onChange(of: locationModel.customPathField) {
                            locationModel.validateCustomPath()
                        }

                        Button("Choose…") { chooseCustomPrefix() }
                            .fixedSize()
                    }
                    .disabled(locationModel.selection != .custom)

                    if locationModel.invalidSelection {
                        Label(
                            "Currently selected brew path is invalid",
                            systemImage: "xmark.circle.fill"
                        )
                        .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Library") {
                LabeledContent("Installed Casks", value: "\(localHomebrew.installedCaskCount)")
                LabeledContent(
                    "Last Scan",
                    value: localHomebrew.lastRefresh?.formatted(date: .abbreviated, time: .shortened)
                        ?? String(localized: "Never")
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { locationModel.synchronize() }
        .onChange(of: localHomebrew.customBrewPrefix) {
            locationModel.synchronize()
        }
    }

    private func locationOption(
        _ choice: HomebrewLocationChoice,
        title: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(title)
                if locationModel.selection == choice {
                    Image(systemName: locationModel.invalidSelection
                          ? "xmark.circle.fill"
                          : "checkmark.circle.fill")
                        .foregroundStyle(locationModel.invalidSelection ? .red : .green)
                        .accessibilityHidden(true)
                }
            }
            if let path = choice.brewBinaryPath {
                Text(path)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func chooseCustomPrefix() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = String(
            localized: "Select the brew binary or the Homebrew installation folder"
        )
        let response = CrashReporter.withHangTrackingPaused { panel.runModal() }
        guard response == .OK, let url = panel.url else { return }
        Task { await locationModel.applySelection(url) }
    }
}

struct PrivacySettingsView: View {
    @AppStorage(Analytics.enabledKey) private var analyticsEnabled = true
    @AppStorage(CrashReporter.enabledKey) private var crashReportingEnabled = true

    var body: some View {
        Form {
            Section("Usage Analytics") {
                Toggle(
                    "Share anonymous usage analytics",
                    isOn: $analyticsEnabled
                )

                Text(.settingsPrivacyUsageAnalytics)
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Crash Reports") {
                Toggle(
                    "Share crash reports",
                    isOn: $crashReportingEnabled
                )

                Text(.settingsPrivacyCrashReports)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
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
    SettingsView(selection: .constant(.general))
        .environment(UpdaterService())
        .environment(LocalHomebrewService())
}
