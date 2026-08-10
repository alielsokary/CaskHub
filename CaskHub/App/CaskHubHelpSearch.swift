//
//  CaskHubHelpSearch.swift
//  CaskHub
//
//  Created by Ali Elsokary on 09/08/2026.
//

import AppKit
import SwiftUI

@MainActor
final class CaskHubHelpSearchHandler: NSObject, NSUserInterfaceItemSearching {
    typealias SelectionAction = @MainActor (HelpTopic) -> Void

    var onSelect: SelectionAction

    nonisolated private let items = HelpTopic.allCases.map {
        SearchItem(
            topic: $0,
            title: $0.helpMenuTitle,
            searchText: ([$0.helpMenuTitle, $0.title] + $0.searchKeywords)
                .joined(separator: " ")
        )
    }

    init(onSelect: @escaping SelectionAction = { _ in }) {
        self.onSelect = onSelect
    }

    nonisolated func searchForItems(
        withSearch searchString: String,
        resultLimit: Int,
        matchedItemHandler handleMatchedItems: @escaping ([Any]) -> Void
    ) {
        guard resultLimit > 0 else {
            handleMatchedItems([])
            return
        }

        let query = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            handleMatchedItems([])
            return
        }

        let queryTerms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let matches = items.lazy
            .filter { item in
                queryTerms.allSatisfy {
                    item.searchText.localizedCaseInsensitiveContains($0)
                }
            }
            .prefix(resultLimit)
        handleMatchedItems(Array(matches))
    }

    nonisolated func localizedTitles(forItem item: Any) -> [String] {
        guard let item = item as? SearchItem else { return [] }
        return [item.title]
    }

    nonisolated func performAction(forItem item: Any) {
        guard let item = item as? SearchItem else { return }
        Task { @MainActor in
            self.onSelect(item.topic)
        }
    }
}

nonisolated extension HelpTopic {
    var helpMenuTitle: String {
        switch self {
        case .gettingStarted: "CaskHub Help"
        case .homebrew: "Homebrew Setup"
        case .installAndUpdate: "Updating Apps"
        case .adoption: "Adopting Apps"
        case .permissions: "App Management Permission"
        case .troubleshooting: "Troubleshooting"
        }
    }

    fileprivate var searchKeywords: [String] {
        switch self {
        case .gettingStarted:
            ["welcome", "browse", "catalog", "discover", "manage"]
        case .homebrew:
            ["brew", "install homebrew", "setup", "binary", "custom location", "prefix"]
        case .installAndUpdate:
            ["install", "update", "upgrade", "greedy", "download", "cancel"]
        case .adoption:
            ["adopt", "existing app", "package installer", "manage app"]
        case .permissions:
            ["permission", "privacy", "security", "app management", "system settings"]
        case .troubleshooting:
            ["error", "failure", "repair", "replace", "reinstall", "diagnose"]
        }
    }
}

private struct SearchItem: Sendable {
    let topic: HelpTopic
    let title: String
    let searchText: String
}

@MainActor
struct CaskHubHelpSearchRegistration: NSViewRepresentable {
    @Binding var selection: HelpTopic
    @Environment(\.openWindow) private var openWindow

    func makeCoordinator() -> CaskHubHelpSearchHandler {
        CaskHubHelpSearchHandler()
    }

    func makeNSView(context: Context) -> NSView {
        updateSelectionAction(on: context.coordinator)
        NSApp.registerUserInterfaceItemSearchHandler(context.coordinator)
        return NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        updateSelectionAction(on: context.coordinator)
    }

    static func dismantleNSView(
        _ view: NSView,
        coordinator: CaskHubHelpSearchHandler
    ) {
        NSApp.unregisterUserInterfaceItemSearchHandler(coordinator)
    }

    private func updateSelectionAction(on handler: CaskHubHelpSearchHandler) {
        handler.onSelect = { topic in
            selection = topic
            openWindow(id: CaskHubWindowID.help)
        }
    }
}
