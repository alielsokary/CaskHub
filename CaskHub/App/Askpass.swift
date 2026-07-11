//
//  Askpass.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/07/2026.
//

import AppKit

/// The `--askpass` program mode: sudo re-launches this binary as its
/// SUDO_ASKPASS helper (script written by
/// `LocalHomebrewService.ensureAskpassScript`) and reads the password
/// from stdout.
enum Askpass {
    /// Prints the password to stdout for sudo on "Allow"; exits 1 on cancel
    /// so sudo — and the brew install — abort cleanly.
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

        app.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { exit(1) }
        print(passwordField.stringValue)
        exit(0)
    }
}
