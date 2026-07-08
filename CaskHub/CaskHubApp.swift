//
//  CaskHubApp.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/02/2026.
//

import SwiftUI

@main
struct CaskHubApp: App {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

    init() {
        BrandFonts.register()
        // Apply before any window exists — state restoration can otherwise
        // revive an appearance archived under an older theme setting.
        Self.applyAppearance(UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.system.rawValue)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1380, minHeight: 640)
                .onChange(of: selectedTheme, initial: true) { _, newValue in
                    Self.applyAppearance(newValue)
                }
        }
        .defaultSize(width: 1360, height: 880)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
        }
    }

    /// Theme switching via NSApp.appearance instead of preferredColorScheme:
    /// the window backdrop (containerBackground) and the dynamic NSColor tokens
    /// then resolve against the same appearance. preferredColorScheme(nil)
    /// left the two out of sync after a Light/Dark → System switch.
    private static func applyAppearance(_ raw: String) {
        // NSApplication.shared, not NSApp — NSApp is still nil during App.init().
        let app = NSApplication.shared
        switch AppTheme(rawValue: raw) ?? .system {
        case .system: app.appearance = nil
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
