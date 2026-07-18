//
//  SidebarItem.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import Foundation

// MARK: - Fixed Sidebar Items

enum DiscoverItem: String, CaseIterable, Identifiable {
    case browse = "Browse"
    case featured = "Featured"
    case topCharts = "Top Charts"
    case recentlyAdded = "Recently Added"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .browse: return "square.grid.2x2"
        case .featured: return "star"
        case .topCharts: return "chart.line.uptrend.xyaxis"
        case .recentlyAdded: return "clock.badge.checkmark"
        }
    }
}

enum LibraryItem: String, CaseIterable, Identifiable {
    case installed = "Installed"
    case updates = "Updates"
    case adopt = "Adopt Apps"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .installed: return "arrow.down.to.line"
        case .updates: return "arrow.triangle.2.circlepath"
        case .adopt: return "tray.and.arrow.down"
        }
    }
}

// MARK: - Sidebar Selection

enum SidebarSelection: Hashable, Identifiable {
    case discover(DiscoverItem)
    case library(LibraryItem)
    case category(String)

    var id: String {
        switch self {
        case let .discover(item): return "discover.\(item.rawValue)"
        case let .library(item): return "library.\(item.rawValue)"
        case let .category(categoryID): return "category.\(categoryID)"
        }
    }
}
