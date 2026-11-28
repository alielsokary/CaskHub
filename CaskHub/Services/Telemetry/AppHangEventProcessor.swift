//
//  AppHangEventProcessor.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/11/2026.
//

import Foundation
import Sentry

nonisolated enum AppHangFamily: String, Sendable {
    case appCode = "app-code"
    case sentry
    case sparkle
    case swiftUI = "swift-ui"
    case windowServer = "window-server"
    case graphics
    case appKit = "app-kit"
    case system

    /// `graphics` becomes `CaskHub.GraphicsHang`.
    var issueType: String {
        let name = switch self {
        case .appCode: "AppCode"
        case .sentry: "Sentry"
        case .sparkle: "Sparkle"
        case .swiftUI: "SwiftUI"
        case .windowServer: "WindowServer"
        case .graphics: "Graphics"
        case .appKit: "AppKit"
        case .system: "System"
        }
        return "CaskHub.\(name)Hang"
    }
}

nonisolated final class AppHangEventProcessor: Sendable {
    private static let swiftUIFrameworks = ["swiftui", "attributegraph"]
    private static let graphicsFrameworks = ["coregraphics", "metal", "renderbox"]
    private static let plumbing: Set = ["libdispatch.dylib", "libobjc.A.dylib", "libc++.1.dylib", "libc++abi.dylib", "dyld"]
    private static let lowMemoryBytes: UInt64 = 500 * 1024 * 1024

    func process(_ event: Event) -> Event? {
        guard let exception = event.exceptions?.first(where: {
            $0.mechanism?.type == "AppHang"
        }) else {
            return event
        }

        let frames = exception.stacktrace?.frames
            ?? event.threads?.first(where: { $0.isMain?.boolValue == true })?.stacktrace?.frames
            ?? []
        let family = Self.family(for: frames)
        let chain = Self.frameworkChain(frames)
        var tags = event.tags ?? [:]
        tags["app_hang.family"] = family.rawValue
        tags["app_hang.frameworks"] = chain
        if let free = (event.context?["device"]?["free_memory"] as? NSNumber)?.uint64Value, free < Self.lowMemoryBytes {
            tags["app_hang.low_memory"] = "true"
        }
        event.tags = tags
        exception.type = family.issueType
        if !chain.isEmpty { exception.value = chain }
        // CaskHub's own frames group a hang more precisely than any framework chain.
        event.fingerprint = family == .appCode
            ? ["{{ default }}", "app-hang", family.rawValue]
            : ["app-hang", family.rawValue, chain]
        return event
    }

    /// The first three frameworks above the blocked frame; frames carry no function names on the device.
    private static func frameworkChain(_ frames: [Frame]) -> String {
        var names: [String] = []
        for frame in frames.reversed() {
            guard let package = frame.package else { continue }
            let name = URL(fileURLWithPath: package).lastPathComponent
            guard !name.hasPrefix("libsystem_"), !name.hasPrefix("libobjcMsgSend"), !plumbing.contains(name),
                  !names.contains(name) else { continue }
            names.append(name)
            if names.count == 3 { break }
        }
        return names.joined(separator: " › ")
    }

    private static func family(for frames: [Frame]) -> AppHangFamily {
        // Sentry stores native frames oldest-to-youngest. The youngest useful
        // frame describes the work that was actually blocking the main thread.
        for frame in frames.reversed() {
            if frame.inApp?.boolValue == true {
                return .appCode
            }
            guard let package = frame.package.map({
                URL(fileURLWithPath: $0).lastPathComponent.lowercased()
            }) else { continue }
            if let family = family(forPackage: package) {
                return family
            }
        }
        return .system
    }

    private static func family(forPackage package: String) -> AppHangFamily? {
        if package.contains("sentry") { return .sentry }
        if package.contains("sparkle") { return .sparkle }
        if swiftUIFrameworks.contains(where: package.contains) { return .swiftUI }
        if package == "skylight" { return .windowServer }
        if graphicsFrameworks.contains(where: package.contains) { return .graphics }
        if package == "appkit" { return .appKit }
        return nil
    }
}
