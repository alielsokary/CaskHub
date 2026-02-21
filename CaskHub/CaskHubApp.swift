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

    private var colorScheme: ColorScheme? {
        (AppTheme(rawValue: selectedTheme) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorScheme)
        }

        Settings {
            SettingsView()
        }
    }
}
