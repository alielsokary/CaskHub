//
//  CaskHubApp.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/02/2026.
//

import SwiftUI

/// Branches before SwiftUI starts: when sudo launches this binary as its
/// SUDO_ASKPASS helper (`--askpass <token>`), show a native password alert
/// instead of booting the app.
@main
enum CaskHubMain {
    static func main() {
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--askpass") {
            let token = CommandLine.arguments.indices.contains(flagIndex + 1)
                ? CommandLine.arguments[flagIndex + 1] : nil
            runAskpassDialog(token: token)
        }
        CaskHubApp.main()
    }

    /// Prints the password to stdout for sudo on "Allow"; exits 1 on cancel
    /// so sudo — and the brew install — abort cleanly.
    private static func runAskpassDialog(token: String?) -> Never {
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

struct CaskHubApp: App {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

    init() {
        BrandFonts.register()
        Analytics.start()
        // Apply before any window exists — state restoration can otherwise
        // revive an appearance archived under an older theme setting.
        Self.applyAppearance(UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.system.rawValue)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1380, minHeight: 640)
                .onChange(of: selectedTheme, initial: true) { _, newValue in
                    Self.applyAppearance(newValue)
                }
        }
        .defaultSize(width: 1360, height: 880)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
        }
    }

    /// Theme switching via NSApp.appearance instead of preferredColorScheme:
    /// the window backdrop (containerBackground) and the dynamic NSColor tokens
    /// then resolve against the same appearance. preferredColorScheme(nil)
    /// left the two out of sync after a Light/Dark → System switch.
    private static func applyAppearance(_ raw: String) {
        // NSApplication.shared, not NSApp — NSApp is still nil during App.init().
        let app = NSApplication.shared
        switch AppTheme(rawValue: raw) ?? .system {
        case .system: app.appearance = nil
        case .light: app.appearance = NSAppearance(named: .aqua)
        case .dark: app.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
