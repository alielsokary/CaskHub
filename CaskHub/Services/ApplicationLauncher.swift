//
//  ApplicationLauncher.swift
//  CaskHub
//
//  Created by Ali Elsokary on 25/07/2026.
//

import AppKit

@MainActor
protocol ApplicationLaunching {
    func open(_ url: URL)
}

@MainActor
struct WorkspaceApplicationLauncher: ApplicationLaunching {
    func open(_ url: URL) {
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }
}
