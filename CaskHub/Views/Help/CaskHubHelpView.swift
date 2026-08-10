//
//  CaskHubHelpView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/08/2026.
//

import SwiftUI

enum CaskHubLinks {
    static let website = URL(string: "https://caskhub.app")!
    static let repository = URL(string: "https://github.com/alielsokary/CaskHub")!
    static let issues = URL(string: "https://github.com/alielsokary/CaskHub/issues/new/choose")!
    static let homebrew = URL(string: "https://brew.sh")!
}

nonisolated enum HelpTopic: String, CaseIterable, Identifiable, Sendable {
    case gettingStarted
    case homebrew
    case installAndUpdate
    case adoption
    case permissions
    case troubleshooting

    var id: Self { self }

    var title: String {
        switch self {
        case .gettingStarted: String(localized: "Getting Started")
        case .homebrew: String(localized: "Homebrew Setup")
        case .installAndUpdate: String(localized: "Install & Update")
        case .adoption: String(localized: "Adopting Apps")
        case .permissions: String(localized: "Permissions")
        case .troubleshooting: String(localized: "Troubleshooting")
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted: "sparkles"
        case .homebrew: "shippingbox"
        case .installAndUpdate: "arrow.down.circle"
        case .adoption: "arrow.triangle.2.circlepath"
        case .permissions: "hand.raised"
        case .troubleshooting: "wrench.and.screwdriver"
        }
    }
}

struct CaskHubHelpView: View {
    @Binding var selection: HelpTopic
    @Binding var settingsSelection: SettingsSection
    let navigateToCatalog: (SidebarSelection) -> Void

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SidebarView.showAdoptKey) private var showAdoptApps = true

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.icon)
                    .tag(topic)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            ScrollView {
                topicContent
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(32)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(Color.chTerracotta)
    }

    @ViewBuilder
    private var topicContent: some View {
        switch selection {
        case .gettingStarted:
            HelpPage(
                title: "Welcome to CaskHub",
                subtitle: .helpGettingStartedSubtitle
            ) {
                HelpSection(title: "Browse", icon: "square.grid.2x2") {
                    Text(.helpBrowseOverview)
                }

                HelpSection(title: "Manage", icon: "shippingbox") {
                    Text(.helpManageOverview)
                }

                HStack {
                    Button("Browse Apps") {
                        openCatalog(.discover(.browse))
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Check Homebrew Setup") {
                        selection = .homebrew
                    }
                }
            }

        case .homebrew:
            HelpPage(
                title: "Homebrew Setup",
                subtitle: .helpHomebrewSubtitle
            ) {
                HelpSection(title: "Current Status", icon: homebrewStatusIcon) {
                    Text(homebrewStatusText)

                    if localHomebrew.brewVersion == nil {
                        Text(.helpHomebrewInstall)
                    }
                }

                HelpSection(title: "Custom Locations", icon: "folder") {
                    Text(.helpHomebrewCustomLocation)
                }

                HStack {
                    Link("Open brew.sh", destination: CaskHubLinks.homebrew)
                        .buttonStyle(.borderedProminent)

                    Button("Open Homebrew Settings") {
                        openSettings(section: .homebrew)
                    }
                }
            }

        case .installAndUpdate:
            HelpPage(
                title: "Install & Update",
                subtitle: .helpInstallAndUpdateSubtitle
            ) {
                HelpSection(title: "Installing", icon: "arrow.down.circle") {
                    Text(.helpInstallHowTo)
                }

                HelpSection(title: "Updating", icon: "arrow.triangle.2.circlepath") {
                    Text(.helpUpdatesOverview)
                }

                HelpSection(title: "Greedy Updates", icon: "checkmark.circle") {
                    Text(.helpUpdatesGreedy)
                }

                Button("Show Available Updates") {
                    openCatalog(.library(.updates))
                }
                .buttonStyle(.borderedProminent)
            }

        case .adoption:
            HelpPage(
                title: "Adopting Apps",
                subtitle: .helpAdoptionSubtitle
            ) {
                HelpSection(title: "What Changes", icon: "arrow.triangle.2.circlepath") {
                    Text(.helpAdoptWhatChanges)
                }

                HelpSection(title: "Package Installers", icon: "shippingbox.fill") {
                    Text(.helpAdoptPackageInstallers)
                }

                HelpSection(title: "When Adoption Cannot Continue", icon: "exclamationmark.triangle") {
                    Text(.helpAdoptMismatch)
                }

                Button("Show Adoptable Apps") {
                    showAdoptApps = true
                    openCatalog(.library(.adopt))
                }
                .buttonStyle(.borderedProminent)
            }

        case .permissions:
            HelpPage(
                title: "App Management Permission",
                subtitle: .helpPermissionsSubtitle
            ) {
                HelpSection(title: "Why It Is Needed", icon: "hand.raised") {
                    Text(.helpPermissionsWhy)
                }

                HelpSection(title: "How to Grant It", icon: "gearshape") {
                    Text(.helpPermissionsGrant)
                }

                HStack {
                    Button("Open System Settings") {
                        AppManagementPermission.openSystemSettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("View Permission Status") {
                        openSettings(section: .general)
                    }
                }
            }

        case .troubleshooting:
            HelpPage(
                title: "Troubleshooting",
                subtitle: .helpTroubleshootingSubtitle
            ) {
                HelpSection(title: "Homebrew Not Found", icon: "magnifyingglass") {
                    Text(.helpTroubleshootingHomebrewMissing)
                }

                HelpSection(title: "Permission Denied", icon: "lock") {
                    Text(.helpTroubleshootingPermissionDenied)
                }

                HelpSection(title: "Repair or Replace", icon: "wrench.and.screwdriver") {
                    Text(.helpTroubleshootingRecovery)
                }

                HStack {
                    Button("Open Homebrew Settings") {
                        openSettings(section: .homebrew)
                    }
                    .buttonStyle(.borderedProminent)

                    Link("Report an Issue", destination: CaskHubLinks.issues)
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var homebrewStatusIcon: String {
        localHomebrew.brewVersion == nil ? "xmark.circle" : "checkmark.circle.fill"
    }

    private var homebrewStatusText: String {
        guard let version = localHomebrew.brewVersion else {
            return String(localized: "Homebrew was not found on this Mac.")
        }
        return String(localized: "Homebrew is available: \(version)")
    }

    private func openCatalog(_ destination: SidebarSelection) {
        navigateToCatalog(destination)
        openWindow(id: CaskHubWindowID.main)
    }

    private func openSettings(section: SettingsSection) {
        settingsSelection = section
        openSettings()
    }
}

private struct HelpPage<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
    }
}

private struct HelpSection<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.headline)
                content
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

#Preview {
    CaskHubHelpView(
        selection: .constant(.gettingStarted),
        settingsSelection: .constant(.general),
        navigateToCatalog: { _ in }
    )
    .environment(LocalHomebrewService())
    .frame(width: 880, height: 620)
}
