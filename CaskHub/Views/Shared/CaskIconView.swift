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
    var alignment: Alignment = .top

    @Environment(ImageCacheService.self) private var imageCache
    @State private var loadedImage: NSImage?
    @State private var didResolve = false

    private var shadowInset: CGFloat { size * IconBitmap.shadowInset }

    private var wellShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
    }

    var body: some View {
        ZStack {
            if let image = imageCache.cachedImage(for: cask.token) ?? loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size + shadowInset * 2, height: size + shadowInset * 2, alignment: alignment)
                    .padding(-shadowInset)
                    .transition(.opacity)
            } else if cask.isCLI {
                cliTile
            } else if cask.isFont {
                fontTile
            } else {
                well(.chSurfaceWell)
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
        .task(id: [cask.token, imageCache.iconHash(for: cask.token) ?? "", String(imageCache.iconRefreshRevision)]) {
            didResolve = false
            let image = await imageCache.image(for: cask)
            guard !Task.isCancelled else { return }
            loadedImage = image
            didResolve = true
        }
    }

    private var cliTile: some View {
        well(.chSurfaceTerminal)
            .overlay(
                Text(">_")
                    .font(Font.custom(CHType.monoFamily, size: size * 0.34).weight(.bold))
                    .foregroundStyle(Color.chCream)
            )
    }

    private var fontTile: some View {
        well(.chSurfaceWell)
            .overlay(
                Text(verbatim: "Aa")
                    .font(.system(size: size * 0.4, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.chTextTitle)
            )
    }

    private func well(_ fill: Color) -> some View {
        wellShape
            .fill(fill)
            .overlay(wellShape.strokeBorder(Color.chHairline, lineWidth: 0.5))
            .frame(width: size, height: size)
    }
}

#if DEBUG
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
#endif
