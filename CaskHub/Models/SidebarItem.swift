//
//  SidebarItem.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import Foundation

enum SidebarSection: String, CaseIterable {
    case discover = "DISCOVER"
    case library = "LIBRARY"
    case categories = "CATEGORIES"
}

enum SidebarItem: String, Hashable, Identifiable, CaseIterable {
    // Discover
    case browse = "Browse"
    case featured = "Featured"
    case topCharts = "Top Charts"

    // Library
    case installed = "Installed"
    case updates = "Updates"

    // Categories
    case development = "Development"
    case design = "Design"
    case productivity = "Productivity"
    case finance = "Finance"
    case tools = "Tools"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .browse: return "globe"
        case .featured: return "star"
        case .topCharts: return "chart.line.uptrend.xyaxis"
        case .installed: return "arrow.down.to.line"
        case .updates: return "arrow.triangle.2.circlepath"
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .design: return "paintbrush"
        case .productivity: return "briefcase"
        case .finance: return "dollarsign"
        case .tools: return "wrench"
        }
    }

    var section: SidebarSection {
        switch self {
        case .browse, .featured, .topCharts: return .discover
        case .installed, .updates: return .library
        case .development, .design, .productivity, .finance, .tools: return .categories
        }
    }

    static func items(for section: SidebarSection) -> [SidebarItem] {
        allCases.filter { $0.section == section }
    }
}
