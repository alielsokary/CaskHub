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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(.quaternary)
                .frame(width: size, height: size)

            if let loadedImage {
                Image(nsImage: loadedImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
                    .transition(.opacity)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeIn(duration: 0.2), value: loadedImage != nil)
        .task(id: cask.token) {
            loadedImage = await imageCache.image(for: cask)
        }
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
    .environment(ImageCacheService())
}
