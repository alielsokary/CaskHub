//
//  SettingsView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import AppKit
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
            HomebrewSettingsView()
                .tabItem {
                    Label("Homebrew", systemImage: "shippingbox")
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
    @State private var settingsModel: GeneralSettingsModel
    @AppStorage(SidebarView.showAdoptKey) private var showAdoptApps = true
    @AppStorage(UpdaterService.showUpdatePromptKey) private var showUpdatePrompt = true

    init(settingsModel: GeneralSettingsModel? = nil) {
        _settingsModel = State(initialValue: settingsModel ?? GeneralSettingsModel())
    }

    var body: some View {
        @Bindable var updater = updater
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
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                Toggle("Show update notification at launch", isOn: $showUpdatePrompt)
                Text("""
                Updates always download in the background. When this is off, they \
                install silently the next time you quit CaskHub instead of showing \
                what's new first.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Section("Sidebar") {
                Toggle("Show Adopt Apps", isOn: $showAdoptApps)
                Text("Adopt Apps lists installed apps that Homebrew can start managing for you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                Text("""
                Needed to adopt or update apps whose casks modify the app bundle \
                (macOS otherwise blocks CaskHub from modifying other apps). Enable \
                CaskHub under System Settings → Privacy & Security → App Management.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Section("Storage") {
                LabeledContent("Clear cached app icons") {
                    Button("Clear Cache") {
                        Task { await imageCache.clearCache() }
                    }
                }
                Text("Removes cached app icons. They re-download the next time each app is shown.")
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

    private func badge(_ title: String, icon: String, tint: some ShapeStyle) -> some View {
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
                pathRow("Brew Binary", HomebrewLocator.brewBinaryURL()?.path)
                pathRow(
                    "Caskroom",
                    HomebrewLocator.caskroomURL(fileManager: .default)?.path
                )
            }
            Section("Library") {
                LabeledContent("Installed Casks", value: "\(localHomebrew.installedCasks.count)")
                LabeledContent(
                    "Last Scan",
                    value: localHomebrew.lastRefresh?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
                )
            }
            Section("Custom Location") {
                LabeledContent("Custom Path") {
                    HStack(spacing: 10) {
                        TextField("", text: $locationModel.customPathField, prompt: Text(""))
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 220)
                            .onSubmit {
                                Task { await locationModel.applyTypedPath() }
                            }
                        Button("Choose…") { chooseCustomPrefix() }
                    }
                }
                Text("""
                Point CaskHub at a Homebrew installed outside the standard locations \
                (/opt/homebrew and /usr/local). Select the brew binary or its \
                installation folder.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { locationModel.synchronize() }
        .onChange(of: localHomebrew.customBrewPrefix) {
            locationModel.synchronize()
        }
        .alert(
            "No Homebrew There",
            isPresented: Binding(
                get: { locationModel.invalidSelection },
                set: { if !$0 { locationModel.dismissInvalidSelection() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The selected location doesn't contain a brew binary.")
        }
    }

    private func pathRow(_ title: String, _ path: String?) -> some View {
        LabeledContent(title) {
            Text(path ?? "Not found")
                .font(.callout.monospaced())
                .foregroundStyle(path == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func chooseCustomPrefix() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Select the brew binary or the Homebrew installation folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await locationModel.applySelection(url) }
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
        .environment(LocalHomebrewService())
}
