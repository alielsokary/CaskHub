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
}

nonisolated final class AppHangEventProcessor: Sendable {
    private static let swiftUIFrameworks = ["swiftui", "attributegraph"]
    private static let graphicsFrameworks = ["coregraphics", "metal", "renderbox"]

    func process(_ event: Event) -> Event? {
        guard let exception = event.exceptions?.first(where: {
            $0.mechanism?.type == "AppHang"
        }) else {
            return event
        }

        let family = Self.family(
            for: exception.stacktrace?.frames
                ?? event.threads?.first(where: { $0.isMain?.boolValue == true })?
                    .stacktrace?.frames
                ?? []
        )
        var tags = event.tags ?? [:]
        tags["app_hang.family"] = family.rawValue
        event.tags = tags
        event.fingerprint = (event.fingerprint ?? ["{{ default }}"])
            + ["app-hang", family.rawValue]
        return event
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
