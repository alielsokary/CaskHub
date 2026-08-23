//
//  Askpass.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/07/2026.
//

import AppKit

enum Askpass {
    static func runDialog(token: String?, cancellationMarker: URL?) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let alert = NSAlert()
        alert.messageText = String(localized: "CaskHub needs administrator access")
        alert.informativeText = token.map {
            String(localized: "The installer for “\($0)” requires your login password.")
        } ?? String(localized: "This installer requires your login password.")
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 230, height: 24))
        alert.accessoryView = passwordField
        alert.window.initialFirstResponder = passwordField

        // Activation is cooperative; the floating level keeps the prompt on top.
        alert.window.level = .floating
        app.activate()
        app.requestUserAttention(.criticalRequest)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn,
              !passwordField.stringValue.isEmpty
        else {
            if let cancellationMarker {
                try? Data().write(to: cancellationMarker, options: .atomic)
            }
            exit(1)
        }
        print(passwordField.stringValue)
        exit(0)
    }
}
