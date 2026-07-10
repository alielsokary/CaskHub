//
//  CaskIconView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import SwiftUI

struct CaskIconView: View {
    let cask: Cask
    var size: CGFloat = 44

    @Environment(ImageCacheService.self) private var imageCache
    @State private var loadedImage: NSImage?

    private var wellShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
    }

    var body: some View {
        ZStack {
            if let loadedImage {
                wellShape
                    .fill(Color.chSurfaceField)
                    .overlay(wellShape.strokeBorder(Color.chHairlineStrong, lineWidth: 1))
                    .frame(width: size, height: size)
                Image(nsImage: loadedImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.8, height: size * 0.8)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
                    .transition(.opacity)
            } else if cask.isCLI {
                // CLI casks hold no icon at the source — a branded terminal
                // tile is their placeholder. CaskFlow's icons branch decides
                // the exceptions (Android SDK tools, tuist, conda family):
                // whatever it serves loads like any other icon.
                cliTile
            } else {
                wellShape
                    .fill(Color.chSurfaceField)
                    .overlay(wellShape.strokeBorder(Color.chHairlineStrong, lineWidth: 1))
                    .frame(width: size, height: size)
                Image(systemName: "macwindow")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Color.chTextMuted)
            }
        }
        .animation(.easeIn(duration: 0.2), value: loadedImage != nil)
        .task(id: cask.token) {
            loadedImage = await imageCache.image(for: cask)
        }
    }

    private var cliTile: some View {
        wellShape
            .fill(Color.chInk)
            .overlay(wellShape.strokeBorder(Color.chHairlineStrong, lineWidth: 1))
            .overlay(
                Text(">_")
                    .font(Font.custom(CHType.monoFamily, size: size * 0.34).weight(.bold))
                    .foregroundStyle(Color.chCream)
            )
            .frame(width: size, height: size)
    }
}

#Preview {
    let sampleCask = Cask(
        token: "firefox",
        fullToken: nil,
        tap: nil,
        name: ["Firefox"],
        desc: "Web browser",
        homepage: "https://www.mozilla.org/firefox/",
        url: nil,
        version: "125.0",
        installed: nil,
        bundleVersion: nil,
        bundleShortVersion: nil,
        outdated: false,
        deprecated: false,
        disabled: false,
        autoUpdates: true
    )
    HStack(spacing: 20) {
        CaskIconView(cask: sampleCask, size: 32)
        CaskIconView(cask: sampleCask, size: 44)
        CaskIconView(cask: sampleCask, size: 56)
    }
    .padding()
    .background(Color.chCream)
    .environment(ImageCacheService())
}
