//
//  Analytics+Events.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/07/2026.
//

import Foundation

/// CaskHub's full signal vocabulary, in one place. Call sites go through
/// these typed helpers — never raw signal strings — so everything the app
/// can ever send stays auditable in this single file, and none of it knows
/// which analytics provider is behind `Analytics.send`.
extension Analytics {
    // MARK: - Cask actions

    /// Success signal for install / uninstall / update. App launches
    /// (`.opening`) are deliberately not tracked.
    static func caskActionCompleted(_ action: CaskAction, token: String) {
        guard let verb = action.analyticsVerb else { return }
        send("Cask.\(verb.past)", parameters: ["cask": token])
    }

    static func caskActionFailed(_ action: CaskAction, token: String) {
        guard let verb = action.analyticsVerb else { return }
        send("Cask.actionFailed", parameters: ["action": verb.base, "cask": token])
    }

    /// The Updates page "Update All" tap; each cask in the queue then emits
    /// its own `Cask.updated` / `Cask.actionFailed` signal as usual.
    static func updateAllTapped(count: Int) {
        send("Cask.updateAllTapped", parameters: ["count": "\(count)"])
    }

    // MARK: - Navigation

    /// Fires for every detail-page change: sidebar clicks, category clicks
    /// on cards, and View All — they all route through the same selection.
    static func pageOpened(_ selection: SidebarSelection) {
        send("Page.opened", parameters: parameters(for: selection))
    }

    /// The Browse-shelf "View All" tap, sent alongside the `Page.opened`
    /// the navigation itself produces.
    static func viewAllTapped(to destination: SidebarSelection) {
        send("Browse.viewAllTapped", parameters: parameters(for: destination))
    }

    // MARK: - Search

    static func searchPerformed(query: String, results: Int) {
        send("Search.performed", parameters: [
            "query": query.trimmingCharacters(in: .whitespaces).lowercased(),
            "results": "\(results)"
        ])
    }

    // MARK: - Filters & view options

    static func sortChanged(_ option: SortOption) {
        send("Filter.sortChanged", parameters: ["option": option.rawValue])
    }

    static func topChartsPeriodChanged(_ period: AnalyticsPeriod) {
        send("Filter.periodChanged", parameters: ["period": period.rawValue])
    }

    static func recentWindowChanged(_ window: RecentlyAddedWindow) {
        send("Filter.windowChanged", parameters: ["window": "\(window.rawValue)d"])
    }

    static func viewModeChanged(_ mode: ViewMode) {
        send("View.modeChanged", parameters: ["mode": mode.rawValue])
    }

    // MARK: - Settings

    static func themeChanged(_ theme: String) {
        send("Settings.themeChanged", parameters: ["theme": theme])
    }

    /// Turning telemetry OFF sends nothing — the opt-out applies instantly.
    static func analyticsReEnabled() {
        send("Settings.analyticsEnabled")
    }

    // MARK: - Parameter mapping

    private static func parameters(for selection: SidebarSelection) -> [String: String] {
        switch selection {
        case let .discover(item):
            return ["page": item.analyticsName]
        case let .library(item):
            return ["page": item.rawValue.lowercased()]
        case let .category(categoryID):
            return ["page": "category", "category": categoryID]
        }
    }
}

// MARK: - Analytics names for domain types

private extension CaskAction {
    /// Verb forms for signal names; nil means "don't track this action".
    var analyticsVerb: (base: String, past: String)? {
        switch self {
        case .installing: return ("install", "installed")
        case .uninstalling: return ("uninstall", "uninstalled")
        case .updating: return ("update", "updated")
        case .opening: return nil
        }
    }
}

private extension DiscoverItem {
    var analyticsName: String {
        switch self {
        case .browse: return "browse"
        case .featured: return "featured"
        case .topCharts: return "topCharts"
        case .recentlyAdded: return "recentlyAdded"
        }
    }
}
