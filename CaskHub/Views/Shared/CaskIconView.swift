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
    @State private var didResolve = false

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
                cliTile
            } else {
                wellShape
                    .fill(Color.chSurfaceField)
                    .overlay(wellShape.strokeBorder(Color.chHairlineStrong, lineWidth: 1))
                    .frame(width: size, height: size)
                if didResolve {
                    Image(systemName: "macwindow")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(Color.chTextMuted)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .animation(.easeIn(duration: 0.2), value: loadedImage != nil)
        .task(id: cask.token) {
            didResolve = false
            loadedImage = await imageCache.image(for: cask)
            didResolve = true
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
    let sampleCask = Cask.preview(token: "firefox", name: "Firefox", desc: "Web browser", version: "125.0")
    HStack(spacing: 20) {
        CaskIconView(cask: sampleCask, size: 32)
        CaskIconView(cask: sampleCask, size: 44)
        CaskIconView(cask: sampleCask, size: 56)
    }
    .padding()
    .background(Color.chCream)
    .environment(ImageCacheService())
}
