//
//  ApplicationMenuTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 09/08/2026.
//

@testable import CaskHub
import AppKit
import XCTest

final class ApplicationMenuTests: XCTestCase {
    @MainActor
    func test_help_search_finds_topics_by_title_and_workflow_keywords() throws {
        let searchHandler = CaskHubHelpSearchHandler { _ in }

        let homebrewResults = searchResults(for: "brew", using: searchHandler)
        XCTAssertEqual(
            homebrewResults.flatMap(searchHandler.localizedTitles(forItem:)),
            ["Homebrew Setup"]
        )

        let permissionResults = searchResults(for: "privacy", using: searchHandler)
        XCTAssertEqual(
            permissionResults.flatMap(searchHandler.localizedTitles(forItem:)),
            ["App Management Permission"]
        )

        let updateResults = searchResults(for: "install greedy", using: searchHandler)
        XCTAssertEqual(
            updateResults.flatMap(searchHandler.localizedTitles(forItem:)),
            ["Updating Apps"]
        )

        let limitedResults = searchResults(for: "app", limit: 2, using: searchHandler)
        XCTAssertEqual(limitedResults.count, 2)
    }

    @MainActor
    func test_help_search_selection_routes_to_matching_topic() async throws {
        var selectedTopic: HelpTopic?
        let selectionExpectation = expectation(description: "Help topic selected")
        let searchHandler = CaskHubHelpSearchHandler {
            selectedTopic = $0
            selectionExpectation.fulfill()
        }
        let result = try XCTUnwrap(
            searchResults(for: "adopt", using: searchHandler).first
        )

        searchHandler.performAction(forItem: result)
        await fulfillment(of: [selectionExpectation], timeout: 1)

        XCTAssertEqual(selectedTopic, .adoption)
    }

    @MainActor
    func test_application_menu_contract() throws {
        let mainMenu = try XCTUnwrap(NSApp.mainMenu)
        let topLevelTitles = mainMenu.items.map(\.title)

        XCTAssertFalse(topLevelTitles.contains("File"), "Unexpected menus: \(topLevelTitles)")

        let applicationMenu = try XCTUnwrap(mainMenu.items.first?.submenu)
        let applicationTitles = applicationMenu.items
            .filter { !$0.isSeparatorItem }
            .map(\.title)
        let aboutIndex = try XCTUnwrap(applicationTitles.firstIndex(of: "About CaskHub"))
        let aboutItem = try XCTUnwrap(applicationMenu.item(withTitle: "About CaskHub"))
        XCTAssertNotNil(aboutItem.image)
        let updateIndex = try XCTUnwrap(
            applicationTitles.firstIndex(of: "Check for Updates…")
        )
        XCTAssertLessThan(aboutIndex, updateIndex, "Application menu: \(applicationTitles)")
        let rawAboutIndex = applicationMenu.index(of: aboutItem)
        let updateItem = try XCTUnwrap(applicationMenu.item(withTitle: "Check for Updates…"))
        XCTAssertEqual(applicationMenu.index(of: updateItem), rawAboutIndex + 1)

        let viewMenu = try XCTUnwrap(mainMenu.item(withTitle: "View")?.submenu)
        let viewTitles = viewMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
        let hasSidebarCommand = viewTitles.contains("Show Sidebar")
            || viewTitles.contains("Hide Sidebar")
        XCTAssertTrue(hasSidebarCommand, "View menu: \(viewTitles)")
        XCTAssertTrue(viewTitles.contains("Grid"), "View menu: \(viewTitles)")
        XCTAssertTrue(viewTitles.contains("List"), "View menu: \(viewTitles)")
        XCTAssertFalse(viewTitles.contains("Show Tab Bar"), "View menu: \(viewTitles)")
        XCTAssertFalse(viewTitles.contains("Show All Tabs"), "View menu: \(viewTitles)")

        let windowMenu = try XCTUnwrap(mainMenu.item(withTitle: "Window")?.submenu)
        let windowTitles = windowMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertFalse(windowTitles.contains("CaskHub"), "Window menu: \(windowTitles)")
        XCTAssertFalse(windowTitles.contains("CaskHub Help"), "Window menu: \(windowTitles)")

        let helpMenu = try XCTUnwrap(mainMenu.item(withTitle: "Help")?.submenu)
        let helpTitles = helpMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertTrue(helpTitles.contains("CaskHub Help"), "Help menu: \(helpTitles)")
        XCTAssertTrue(helpTitles.contains("Homebrew Setup"), "Help menu: \(helpTitles)")
        XCTAssertTrue(helpTitles.contains("Adopting Apps"), "Help menu: \(helpTitles)")
        XCTAssertTrue(helpTitles.contains("App Management Permission"), "Help menu: \(helpTitles)")
    }

    @MainActor
    func test_opening_application_menu_preserves_its_items() throws {
        let applicationMenu = try XCTUnwrap(NSApp.mainMenu?.items.first?.submenu)
        let expectedItems = applicationMenuContract(applicationMenu)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            applicationMenu.cancelTracking()
        }
        _ = applicationMenu.popUp(
            positioning: nil,
            at: NSPoint(x: 20, y: 20),
            in: nil
        )

        let openedItems = applicationMenuContract(applicationMenu)
        XCTAssertGreaterThanOrEqual(openedItems.count, expectedItems.count)
        XCTAssertEqual(Array(openedItems.prefix(expectedItems.count)), expectedItems)
    }

    @MainActor
    func test_help_menu_opens_help_window() throws {
        let mainMenu = try XCTUnwrap(NSApp.mainMenu)
        let applicationMenu = try XCTUnwrap(mainMenu.items.first?.submenu)
        let expectedApplicationItems = applicationMenuContract(applicationMenu)
        let expectedApplicationItemIDs = applicationMenu.items.map(ObjectIdentifier.init)
        let helpMenu = try XCTUnwrap(mainMenu.item(withTitle: "Help")?.submenu)
        let helpItem = try XCTUnwrap(helpMenu.item(withTitle: "CaskHub Help"))
        let helpAction = try XCTUnwrap(helpItem.action)
        XCTAssertTrue(NSApp.sendAction(helpAction, to: helpItem.target, from: helpItem))

        let deadline = Date().addingTimeInterval(2)
        while !NSApp.windows.contains(where: { $0.title == "CaskHub Help" }), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        let helpWindow = try XCTUnwrap(
            NSApp.windows.first(where: { $0.title == "CaskHub Help" })
        )
        helpWindow.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let activeApplicationItems = applicationMenuContract(applicationMenu)
        XCTAssertEqual(
            Array(activeApplicationItems.prefix(expectedApplicationItems.count)),
            expectedApplicationItems
        )
        XCTAssertEqual(
            Array(applicationMenu.items.map(ObjectIdentifier.init)
                .prefix(expectedApplicationItemIDs.count)),
            expectedApplicationItemIDs
        )
        addTeardownBlock { @MainActor in
            helpWindow.close()
        }
    }

    @MainActor
    func test_settings_window_keeps_application_menu_items_stable() throws {
        let applicationMenu = try XCTUnwrap(NSApp.mainMenu?.items.first?.submenu)
        let expectedItems = applicationMenuContract(applicationMenu)
        let expectedItemIDs = applicationMenu.items.map(ObjectIdentifier.init)
        let existingWindowIDs = Set(NSApp.windows.map(ObjectIdentifier.init))
        let settingsItem = try XCTUnwrap(applicationMenu.item(withTitle: "Settings…"))
        let settingsAction = try XCTUnwrap(settingsItem.action)

        XCTAssertTrue(NSApp.sendAction(settingsAction, to: settingsItem.target, from: settingsItem))

        let deadline = Date().addingTimeInterval(2)
        while NSApp.windows.allSatisfy({ existingWindowIDs.contains(ObjectIdentifier($0)) }),
              Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        let settingsWindow = try XCTUnwrap(
            NSApp.windows.first(where: { !existingWindowIDs.contains(ObjectIdentifier($0)) })
        )
        settingsWindow.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let activeItems = applicationMenuContract(applicationMenu)
        XCTAssertEqual(Array(activeItems.prefix(expectedItems.count)), expectedItems)
        XCTAssertEqual(
            Array(applicationMenu.items.map(ObjectIdentifier.init).prefix(expectedItemIDs.count)),
            expectedItemIDs
        )
        addTeardownBlock { @MainActor in
            settingsWindow.close()
        }
    }

    @MainActor
    private func searchResults(
        for query: String,
        limit: Int = 10,
        using searchHandler: CaskHubHelpSearchHandler
    ) -> [Any] {
        var results: [Any] = []
        searchHandler.searchForItems(
            withSearch: query,
            resultLimit: limit,
            matchedItemHandler: { results = $0 }
        )
        return results
    }

    @MainActor
    private func applicationMenuContract(_ menu: NSMenu) -> [ApplicationMenuItemContract] {
        menu.items.map {
            ApplicationMenuItemContract(
                title: $0.title,
                isSeparator: $0.isSeparatorItem,
                keyEquivalent: $0.keyEquivalent,
                keyEquivalentModifierMask: $0.keyEquivalentModifierMask,
                hasImage: $0.image != nil,
                hasSubmenu: $0.submenu != nil
            )
        }
    }
}

private struct ApplicationMenuItemContract: Equatable {
    let title: String
    let isSeparator: Bool
    let keyEquivalent: String
    let keyEquivalentModifierMask: NSEvent.ModifierFlags
    let hasImage: Bool
    let hasSubmenu: Bool
}
