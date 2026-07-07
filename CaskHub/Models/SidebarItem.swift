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

    var id: String { rawValue }

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

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .installed: return "arrow.down.to.line"
        case .updates: return "arrow.triangle.2.circlepath"
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
        case .discover(let item): return "discover.\(item.rawValue)"
        case .library(let item): return "library.\(item.rawValue)"
        case .category(let categoryID): return "category.\(categoryID)"
        }
    }

    var displayName: String {
        switch self {
        case .discover(let item): return item.rawValue
        case .library(let item): return item.rawValue
        case .category: return ""
        }
    }
}
