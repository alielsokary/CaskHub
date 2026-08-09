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

    /// Localized label for display. `rawValue` stays language-independent because
    /// it is persisted in `@AppStorage("appTheme")` and used to build asset names.
    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    var previewImage: NSImage? {
        NSImage(named: "ThemePreview-\(rawValue.lowercased())")
    }

    static func apply(_ raw: String) {
        let app = NSApplication.shared
        switch AppTheme(rawValue: raw) ?? .system {
        case .system: app.appearance = nil
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
