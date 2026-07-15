//
//  ContentViewTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 16/07/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

/// Drives ResignFocusOnOutsideClick's local event monitor with a real window
/// and synthetic clicks — the AppKit path a render smoke test can't reach.
final class ContentViewTests: XCTestCase {
    /// Stands in for ContentView's @FocusState: the modifier's closures
    /// read `focused` and bump `resignCount`.
    @MainActor
    private final class FocusProbe {
        var focused = true
        var appeared = false
        private(set) var resignCount = 0
        func resign() { resignCount += 1 }
    }

    // MARK: - Harness

    @MainActor
    private func makeWindow(probe: FocusProbe) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Color.clear
            .modifier(ResignFocusOnOutsideClick(
                isFocused: { probe.focused },
                resign: { probe.resign() }
            ))
            .onAppear { probe.appeared = true })
        window.orderFrontRegardless()

        // Spin the run loop until onAppear has installed the monitor.
        let deadline = Date().addingTimeInterval(2)
        while !probe.appeared, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(probe.appeared, "hosted view never appeared")

        addTeardownBlock { @MainActor in
            window.contentView = NSView() // onDisappear removes the monitor
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.close()
        }
        return window
    }

    /// Sends a left click through NSApp so local monitors observe it. The
    /// matching mouse-up is queued first so no control can stall the test
    /// waiting inside a mouse-tracking loop.
    @MainActor
    private func click(at point: NSPoint, in window: NSWindow) {
        NSApp.postEvent(mouseEvent(.leftMouseUp, at: point, in: window), atStart: false)
        NSApp.sendEvent(mouseEvent(.leftMouseDown, at: point, in: window))
    }

    @MainActor
    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    // MARK: - Tests

    @MainActor
    func test_click_outside_field_editor_resigns_focus() {
        let probe = FocusProbe()
        let window = makeWindow(probe: probe)

        click(at: NSPoint(x: 20, y: 20), in: window)

        XCTAssertEqual(probe.resignCount, 1)
    }

    @MainActor
    func test_click_on_field_editor_keeps_focus() {
        let probe = FocusProbe()
        let window = makeWindow(probe: probe)
        // While a field is focused its text is edited by the window's field
        // editor, an NSTextView — clicks landing on one must keep focus.
        let fieldEditor = NSTextView(frame: NSRect(x: 50, y: 50, width: 100, height: 100))
        fieldEditor.isEditable = false
        fieldEditor.isSelectable = false
        window.contentView!.addSubview(fieldEditor)

        click(at: NSPoint(x: 100, y: 100), in: window)

        XCTAssertEqual(probe.resignCount, 0)
    }

    @MainActor
    func test_click_while_unfocused_is_ignored() {
        let probe = FocusProbe()
        let window = makeWindow(probe: probe)
        probe.focused = false

        click(at: NSPoint(x: 20, y: 20), in: window)

        XCTAssertEqual(probe.resignCount, 0)
    }

    @MainActor
    func test_monitor_is_removed_when_view_disappears() {
        let probe = FocusProbe()
        let window = makeWindow(probe: probe)

        window.contentView = NSView() // onDisappear tears the monitor down
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        click(at: NSPoint(x: 20, y: 20), in: window)

        XCTAssertEqual(probe.resignCount, 0)
    }
}
