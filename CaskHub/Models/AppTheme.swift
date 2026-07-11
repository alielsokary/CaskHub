//
//  AppTheme.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import AppKit

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String {
        rawValue
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// Theme switching via NSApp.appearance instead of preferredColorScheme:
    /// the window backdrop (containerBackground) and the dynamic NSColor tokens
    /// then resolve against the same appearance. preferredColorScheme(nil)
    /// left the two out of sync after a Light/Dark → System switch.
    static func apply(_ raw: String) {
        // NSApplication.shared, not NSApp — NSApp is still nil during App.init().
        let app = NSApplication.shared
        switch AppTheme(rawValue: raw) ?? .system {
        case .system: app.appearance = nil
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
