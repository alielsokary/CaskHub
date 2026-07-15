//
//  AboutView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 16/07/2026.
//

import AppKit
import SwiftUI

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("CaskHub")
                .font(.title.bold())

            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("An App Store for Homebrew casks.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Made with ❤️ by Ali Elsokary")
                .font(.callout)
                .padding(.top, 6)

            Link("github.com/alielsokary/CaskHub",
                 destination: URL(string: "https://github.com/alielsokary/CaskHub")!)
                .font(.callout)
        }
        .padding(32)
        .frame(width: 320)
        .fixedSize()
    }
}

/// Menu item for the About command — lives in a view so it can read
/// `openWindow` from the environment (command Button actions can't).
struct AboutCommandButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About CaskHub") {
            openWindow(id: CaskHubApp.aboutWindowID)
        }
    }
}

#Preview {
    AboutView()
}
