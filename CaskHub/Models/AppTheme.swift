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
