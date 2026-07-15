//
//  CaskHubApp.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/02/2026.
//

import AppKit
import SwiftUI

@main
enum CaskHubMain {
    static func main() {
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--askpass") {
            let token = CommandLine.arguments.indices.contains(flagIndex + 1)
                ? CommandLine.arguments[flagIndex + 1] : nil
            Askpass.runDialog(token: token)
        }
        CaskHubApp.main()
    }
}

struct CaskHubApp: App {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

    @State private var updaterService = UpdaterService()

    @State private var categoryService: CategoryService
    @State private var recentlyAdded: RecentlyAddedService
    @State private var localHomebrew: LocalHomebrewService
    @State private var imageCache = ImageCacheService()
    @State private var catalog: CaskCatalogViewModel

    init() {
        BrandFonts.register()
        CrashReporter.start()
        Analytics.start()
        AppTheme.apply(UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.system.rawValue)

        let categories = CategoryService()
        categories.loadCategories()
        let recent = RecentlyAddedService()
        let homebrew = LocalHomebrewService()
        _categoryService = State(initialValue: categories)
        _recentlyAdded = State(initialValue: recent)
        _localHomebrew = State(initialValue: homebrew)
        _catalog = State(initialValue: CaskCatalogViewModel(
            apiClient: BrewAPIClient(),
            categoryService: categories,
            recentlyAdded: recent,
            localHomebrew: homebrew
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: catalog)
                .frame(minWidth: 1380, minHeight: 640)
                .onChange(of: selectedTheme, initial: true) { _, newValue in
                    AppTheme.apply(newValue)
                }
                .environment(categoryService)
                .environment(recentlyAdded)
                .environment(localHomebrew)
                .environment(imageCache)
        }
        .defaultSize(width: 1360, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About CaskHub") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(
                            string: "Made with ❤️ by Ali Elsokary",
                            attributes: [
                                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                .foregroundColor: NSColor.secondaryLabelColor
                            ]
                        )
                    ])
                }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterService)
            }
        }

        Settings {
            SettingsView()
                .environment(updaterService)
                .environment(imageCache)
        }
    }
}
