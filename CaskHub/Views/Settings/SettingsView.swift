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
            UpdateSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
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
    static let issuesURL = URL(string: "https://github.com/alielsokary/CaskHub/issues/new/choose")!

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

            VStack(alignment: .leading, spacing: 8) {
                Text("Support")
                    .font(.headline)

                GroupBox {
                    HStack(spacing: 12) {
                        Image(systemName: "ladybug")
                            .accessibilityHidden(true)

                        Text("Submit a bug or feature request")

                        Spacer()

                        Link("View", destination: Self.issuesURL)
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
    @Environment(ImageCacheService.self) private var imageCache
    @State private var settingsModel: GeneralSettingsModel
    @AppStorage(SidebarView.showAdoptKey) private var showAdoptApps = true

    init(settingsModel: GeneralSettingsModel? = nil) {
        _settingsModel = State(initialValue: settingsModel ?? GeneralSettingsModel())
    }

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
                LabeledContent("Installed Casks", value: "\(localHomebrew.installedCaskCount)")
                LabeledContent(
                    "Last Scan",
                    value: localHomebrew.lastRefresh?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
                )
            }
            Section("Custom Location") {
                HStack(alignment: .center, spacing: 10) {
                    TextField(
                        "",
                        text: $locationModel.customPathField,
                        prompt: Text("Homebrew path")
                    )
                    .labelsHidden()
                    .accessibilityLabel("Homebrew path")
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                    .onSubmit {
                        Task { await locationModel.applyTypedPath() }
                    }

                    Button("Choose…") { chooseCustomPrefix() }
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
                .controlSize(.regular)

                if localHomebrew.customBrewPrefix != nil {
                    Button("Use Automatic Location") {
                        locationModel.customPathField = ""
                        Task { await locationModel.applyTypedPath() }
                    }
                }

                Text("Only needed when Homebrew is installed outside /opt/homebrew or /usr/local.")
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
            Section("Usage Analytics") {
                Toggle(
                    "Share anonymous usage analytics",
                    isOn: $analyticsEnabled
                )

                Text("""
                Sends anonymized usage signals through TelemetryDeck. No personal \
                information is collected.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Crash Reports") {
                Toggle(
                    "Share crash reports",
                    isOn: $crashReportingEnabled
                )

                Text("""
                Sends crash reports and technical diagnostics through Sentry to help \
                identify and fix problems.
                """)
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
    SettingsView()
        .environment(UpdaterService())
        .environment(ImageCacheService())
        .environment(LocalHomebrewService())
}
