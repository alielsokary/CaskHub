//
//  ContentViewTests.swift
//  CaskHubTests
//
//  Created by Ali Elsokary on 16/07/2026.
//

@testable import CaskHub
import SwiftUI
import XCTest

final class ContentViewTests: XCTestCase {
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

        let deadline = Date().addingTimeInterval(2)
        while !probe.appeared, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(probe.appeared, "hosted view never appeared")

        addTeardownBlock { @MainActor in
            window.contentView = NSView()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.close()
        }
        return window
    }

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

        window.contentView = NSView()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        click(at: NSPoint(x: 20, y: 20), in: window)

        XCTAssertEqual(probe.resignCount, 0)
    }
}

final class TopBarViewTests: XCTestCase {
    private struct TopBarHarness: View {
        let isUpdatingAll: Bool
        let onAppear: () -> Void
        @FocusState private var searchFocused: Bool

        var body: some View {
            TopBarView(
                title: "Updates",
                caskCount: 2,
                sortOption: .constant(.mostPopular),
                viewMode: .constant(.grid),
                searchText: .constant(""),
                searchFocus: $searchFocused,
                onUpdateAll: {},
                isUpdatingAll: isUpdatingAll
            )
            .onAppear(perform: onAppear)
        }
    }

    @MainActor
    private final class RenderProbe {
        var appeared = false
    }

    @MainActor
    private func renderTopBar(isUpdatingAll: Bool) {
        let probe = RenderProbe()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 80),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: TopBarHarness(isUpdatingAll: isUpdatingAll) { probe.appeared = true }
        )
        window.orderFrontRegardless()

        let deadline = Date().addingTimeInterval(2)
        while !probe.appeared, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(probe.appeared, "top bar never rendered")

        window.contentView = NSView()
        window.close()
    }

    @MainActor
    func test_update_all_chip_renders_idle_state() {
        renderTopBar(isUpdatingAll: false)
    }

    @MainActor
    func test_update_all_chip_renders_updating_state() {
        renderTopBar(isUpdatingAll: true)
    }
}
