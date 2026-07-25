#!/usr/bin/env swift

// swiftlint:disable file_length

import AppKit
import ApplicationServices
import Foundation

enum ProfileUIError: Error, CustomStringConvertible {
    case accessibilityPermission
    case action(String, AXError)
    case attribute(String, AXError)
    case control(String)
    case invalidPID(String)
    case usage

    var description: String {
        switch self {
        case .accessibilityPermission:
            return "Accessibility permission is required for the terminal running this script."
        case let .action(name, error):
            return "Accessibility action \(name) failed with error \(error.rawValue)."
        case let .attribute(name, error):
            return "Accessibility attribute \(name) failed with error \(error.rawValue)."
        case let .control(name):
            return "Could not find the \(name) control."
        case let .invalidPID(value):
            return "Invalid process identifier: \(value)"
        case .usage:
            return """
            Usage: script/profile_ui.swift <mode> <pid> [cycles] [start-delay]

              inspect              Print semantic buttons and scroll areas.
              state                Print the selected view mode.
              scroll-position      Print the main content scroll position.
              press-grid           Select grid mode.
              press-list           Select list mode.
              scroll-down          Scroll the main catalog down.
              scroll-up            Scroll the main catalog up.
              workload             Alternate grid/list and scroll.
              sidebar-workload     Cycle through sidebar destinations.
              sidebar-benchmark    Time sidebar AXPress actions without a start delay.
            """
        }
    }
}

struct AppDriver {
    let app: AXUIElement
    let pid: pid_t

    init(pid: pid_t) throws {
        guard AXIsProcessTrusted() else {
            throw ProfileUIError.accessibilityPermission
        }
        self.pid = pid
        app = AXUIElementCreateApplication(pid)
    }

    func attribute(_ name: String, of element: AXUIElement) throws -> CFTypeRef {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success, let value else {
            throw ProfileUIError.attribute(name, error)
        }
        return value
    }

    func optionalAttribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        try? attribute(name, of: element)
    }

    func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        optionalAttribute(name, of: element) as? String
    }

    func children(of element: AXUIElement) -> [AXUIElement] {
        optionalAttribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }

    func descendants(of root: AXUIElement) -> [AXUIElement] {
        var pending = children(of: root)
        var result: [AXUIElement] = []
        while let element = pending.popLast() {
            result.append(element)
            pending.append(contentsOf: children(of: element))
        }
        return result
    }

    func semanticText(of element: AXUIElement) -> String {
        let attributes = [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute,
            kAXValueAttribute
        ]
        let ownText = attributes.compactMap { stringAttribute($0, of: element) }
        let childText = descendants(of: element).flatMap { child in
            attributes.compactMap { stringAttribute($0, of: child) }
        }
        return (ownText + childText).joined(separator: " | ")
    }

    func role(of element: AXUIElement) -> String? {
        stringAttribute(kAXRoleAttribute, of: element)
    }

    func button(containing text: String) throws -> AXUIElement {
        let query = text.lowercased()
        let candidates = descendants(of: app).filter { role(of: $0) == kAXButtonRole }
        guard let match = candidates.first(where: {
            semanticText(of: $0).lowercased().contains(query)
        }) else {
            throw ProfileUIError.control("button containing “\(text)”")
        }
        return match
    }

    func sidebarButton(containing text: String) throws -> AXUIElement {
        let query = text.lowercased()
        let sidebar = try sidebarScrollArea()
        let candidates = descendants(of: sidebar).filter { role(of: $0) == kAXButtonRole }
        guard let match = candidates.first(where: {
            semanticText(of: $0).lowercased().contains(query)
        }) else {
            throw ProfileUIError.control("sidebar button containing “\(text)”")
        }
        return match
    }

    func position(of element: AXUIElement) -> CGPoint? {
        guard let rawValue = optionalAttribute(kAXPositionAttribute, of: element),
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeBitCast(rawValue, to: AXValue.self)
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    func size(of element: AXUIElement) -> CGSize? {
        guard let rawValue = optionalAttribute(kAXSizeAttribute, of: element),
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        let value = unsafeBitCast(rawValue, to: AXValue.self)
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    func mainScrollArea() throws -> AXUIElement {
        let areas = descendants(of: app).filter { role(of: $0) == kAXScrollAreaRole }
        guard let area = areas.max(by: {
            (size(of: $0)?.width ?? 0) < (size(of: $1)?.width ?? 0)
        }) else {
            throw ProfileUIError.control("main content scroll area")
        }
        return area
    }

    func sidebarScrollArea() throws -> AXUIElement {
        let candidates = descendants(of: app).filter {
            guard role(of: $0) == kAXScrollAreaRole, let size = size(of: $0) else {
                return false
            }
            return size.width >= 180 && size.width <= 400 && size.height >= 300
        }
        guard let area = candidates.max(by: {
            (size(of: $0)?.height ?? 0) < (size(of: $1)?.height ?? 0)
        }) else {
            throw ProfileUIError.control("sidebar scroll area")
        }
        return area
    }

    func mainScrollCenter() throws -> CGPoint {
        let area = try mainScrollArea()
        guard let origin = position(of: area), let size = size(of: area) else {
            throw ProfileUIError.control("main content scroll area geometry")
        }
        return CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }

    func perform(_ action: String, on element: AXUIElement) throws {
        let error = AXUIElementPerformAction(element, action as CFString)
        guard error == .success else {
            throw ProfileUIError.action(action, error)
        }
    }

    @discardableResult
    func timedPress(_ element: AXUIElement, label: String) throws -> Double {
        let start = ContinuousClock.now
        try perform(kAXPressAction, on: element)
        let elapsed = start.duration(to: .now)
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        print(String(format: "press_ms\t%@\t%.3f", label, milliseconds))
        return milliseconds
    }

    func raise() throws {
        if AXUIElementPerformAction(app, kAXRaiseAction as CFString) == .success {
            return
        }
        guard let application = NSRunningApplication(processIdentifier: pid) else {
            throw ProfileUIError.control("running application")
        }
        application.activate(options: [.activateAllWindows])
        sleep(0.1)
    }

    func click(at point: CGPoint) throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ),
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw ProfileUIError.control("mouse click event")
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    func scroll(at point: CGPoint, delta: Int32, eventCount: Int = 8) throws {
        try raise()
        let source = CGEventSource(stateID: .combinedSessionState)
        for _ in 0 ..< eventCount {
            guard let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 1,
                wheel1: delta,
                wheel2: 0,
                wheel3: 0
            ) else {
                throw ProfileUIError.control("scroll event")
            }
            event.location = point
            event.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.08)
        }
    }

    func scrollPosition() throws -> String {
        let area = try mainScrollArea()
        guard let rawScrollbar = optionalAttribute(kAXVerticalScrollBarAttribute, of: area),
              CFGetTypeID(rawScrollbar) == AXUIElementGetTypeID() else {
            throw ProfileUIError.control("main content vertical scrollbar")
        }
        let scrollbar = unsafeBitCast(rawScrollbar, to: AXUIElement.self)
        guard let value = optionalAttribute(kAXValueAttribute, of: scrollbar) else {
            throw ProfileUIError.control("main content vertical scrollbar value")
        }
        return String(describing: value)
    }

    func inspect() {
        for element in descendants(of: app) {
            guard let role = role(of: element),
                  role == kAXButtonRole || role == kAXScrollAreaRole else {
                continue
            }
            let sizeDescription = size(of: element).map {
                String(format: "%.0fx%.0f", $0.width, $0.height)
            } ?? "unknown"
            print("\(role)\t\(sizeDescription)\t\(semanticText(of: element))")
        }
    }

    func selectedViewMode() throws -> String {
        let grid = try button(containing: "Grid view")
        let list = try button(containing: "List")
        if isSelected(grid) { return "grid" }
        if isSelected(list) { return "list" }
        if let stored = UserDefaults(suiteName: "com.mag.caskhub")?.string(forKey: "viewMode") {
            return stored
        }
        return "unknown"
    }

    private func isSelected(_ element: AXUIElement) -> Bool {
        for attribute in [kAXSelectedAttribute, kAXValueAttribute] {
            guard let value = optionalAttribute(attribute, of: element) else { continue }
            if let number = value as? NSNumber, number.boolValue {
                return true
            }
            if let string = value as? String, string == "1" {
                return true
            }
        }
        return false
    }
}

func sleep(_ seconds: Double) {
    guard seconds > 0 else { return }
    Thread.sleep(forTimeInterval: seconds)
}

func resolvedSidebarControls(
    driver: AppDriver
) throws -> [(label: String, point: CGPoint)] {
    let labels = [
        "Browse",
        "Installed",
        "Adopt Apps",
        "Browsers",
        "AI & LLMs",
        "Recently Added"
    ]
    let sidebar = try driver.sidebarScrollArea()
    guard let sidebarOrigin = driver.position(of: sidebar),
          let sidebarSize = driver.size(of: sidebar) else {
        throw ProfileUIError.control("sidebar geometry")
    }
    let visibleFrame = CGRect(origin: sidebarOrigin, size: sidebarSize)
    let controls = labels.compactMap { label -> (String, CGPoint)? in
        guard let element = try? driver.sidebarButton(containing: label) else {
            print("missing_control\t\(label)")
            return nil
        }
        guard let origin = driver.position(of: element), let size = driver.size(of: element) else {
            print("missing_geometry\t\(label)")
            return nil
        }
        let point = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        guard visibleFrame.contains(point) else {
            print("offscreen_control\t\(label)")
            return nil
        }
        return (label, point)
    }
    guard controls.count >= 3 else {
        throw ProfileUIError.control("at least three sidebar destinations")
    }
    return controls
}

func runCatalogWorkload(
    driver: AppDriver,
    cycles: Int,
    startDelay: Double
) throws {
    let grid = try driver.button(containing: "Grid view")
    let list = try driver.button(containing: "List")
    let scrollCenter = try driver.mainScrollCenter()
    sleep(startDelay)
    for _ in 0 ..< cycles {
        try driver.timedPress(list, label: "List view")
        sleep(0.35)
        try driver.scroll(at: scrollCenter, delta: -180)
        try driver.scroll(at: scrollCenter, delta: 180)
        try driver.timedPress(grid, label: "Grid view")
        sleep(0.35)
        try driver.scroll(at: scrollCenter, delta: -180)
        try driver.scroll(at: scrollCenter, delta: 180)
    }
}

func runSidebarWorkload(
    driver: AppDriver,
    cycles: Int,
    startDelay: Double,
    settleDelay: Double
) throws {
    let controls = try resolvedSidebarControls(driver: driver)
    try driver.raise()
    sleep(startDelay)
    for _ in 0 ..< cycles {
        for control in controls {
            try driver.click(at: control.point)
            print("click\t\(control.label)")
            sleep(settleDelay)
        }
    }
}

func runSidebarBenchmark(driver: AppDriver, cycles: Int) throws {
    let labels = [
        "Browse",
        "Installed",
        "Adopt Apps",
        "Browsers",
        "Recently Added"
    ]
    try driver.raise()
    for _ in 0 ..< cycles {
        for label in labels {
            let element = try driver.sidebarButton(containing: label)
            try driver.timedPress(element, label: label)
            sleep(0.25)
        }
    }
}

func runSimpleMode(_ mode: String, driver: AppDriver) throws -> Bool {
    switch mode {
    case "inspect":
        driver.inspect()
    case "state":
        print(try driver.selectedViewMode())
    case "scroll-position":
        print(try driver.scrollPosition())
    case "press-grid":
        try driver.timedPress(driver.button(containing: "Grid view"), label: "Grid view")
    case "press-list":
        try driver.timedPress(driver.button(containing: "List"), label: "List view")
    case "scroll-down":
        try driver.scroll(at: driver.mainScrollCenter(), delta: -180)
    case "scroll-up":
        try driver.scroll(at: driver.mainScrollCenter(), delta: 180)
    default:
        return false
    }
    return true
}

func runWorkloadMode(
    _ mode: String,
    driver: AppDriver,
    cycles: Int,
    startDelay: Double
) throws {
    switch mode {
    case "workload":
        try runCatalogWorkload(driver: driver, cycles: cycles, startDelay: startDelay)
    case "sidebar-workload":
        try runSidebarWorkload(
            driver: driver,
            cycles: cycles,
            startDelay: startDelay,
            settleDelay: 0.45
        )
    case "sidebar-benchmark":
        try runSidebarBenchmark(driver: driver, cycles: cycles)
    default:
        throw ProfileUIError.usage
    }
}

func run() throws {
    let arguments = CommandLine.arguments
    guard arguments.count >= 3 else {
        throw ProfileUIError.usage
    }
    let mode = arguments[1]
    guard let pid = pid_t(arguments[2]) else {
        throw ProfileUIError.invalidPID(arguments[2])
    }
    let cycles = arguments.count > 3 ? max(Int(arguments[3]) ?? 1, 1) : 1
    let startDelay = arguments.count > 4 ? max(Double(arguments[4]) ?? 0, 0) : 0
    let driver = try AppDriver(pid: pid)
    guard try !runSimpleMode(mode, driver: driver) else { return }
    try runWorkloadMode(mode, driver: driver, cycles: cycles, startDelay: startDelay)
}

do {
    try run()
} catch {
    fputs("profile_ui: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
