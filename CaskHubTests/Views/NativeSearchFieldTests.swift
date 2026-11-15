//
//  NativeSearchFieldTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 15/11/2026.
//

import AppKit
@testable import CaskHub
import SwiftUI
import XCTest

@MainActor
final class NativeSearchFieldTests: XCTestCase {
    func test_typing_and_clearing_update_the_binding() {
        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })
        let coordinator = NativeSearchField(text: binding, prompt: "Filter").makeCoordinator()
        let field = NSSearchField()

        field.stringValue = "fire"
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertEqual(text, "fire")

        field.stringValue = ""
        coordinator.searchChanged(field)
        XCTAssertEqual(text, "")
    }

    func test_binding_changes_reach_the_field() {
        let hosting = NSHostingView(rootView: NativeSearchField(text: .constant("zed"), prompt: "Filter casks"))
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
        hosting.layoutSubtreeIfNeeded()

        let field = hosting.firstDescendant(of: NSSearchField.self)
        XCTAssertEqual(field?.stringValue, "zed")
        XCTAssertEqual(field?.placeholderString, "Filter casks")
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T ?? subview.firstDescendant(of: type) { return match }
        }
        return nil
    }
}
