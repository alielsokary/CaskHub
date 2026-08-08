//
//  Askpass.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/07/2026.
//

import AppKit

enum Askpass {
    static func runDialog(token: String?) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let alert = NSAlert()
        alert.messageText = "CaskHub needs administrator access"
        alert.informativeText = token.map {
            "The installer for “\($0)” requires your login password."
        } ?? "This installer requires your login password."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 230, height: 24))
        alert.accessoryView = passwordField
        alert.window.initialFirstResponder = passwordField

        // Activation is cooperative; the floating level keeps the prompt on top.
        alert.window.level = .floating
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        app.activate()
        app.requestUserAttention(.criticalRequest)
        guard alert.runModal() == .alertFirstButtonReturn else { exit(1) }
        print(passwordField.stringValue)
        exit(0)
    }
}
