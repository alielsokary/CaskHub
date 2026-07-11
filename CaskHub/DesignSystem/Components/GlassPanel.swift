//
//  GlassPanel.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

// Glass recipe: frosted tinted surface · white hairline (lit from the top) ·
// soft shadow.

private struct GlassPanelModifier: ViewModifier {
    var radius: CGFloat
    var surface: Color
    var shadow: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape
                    .fill(surface)
                    .background(.ultraThinMaterial, in: shape)
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [Color.chHairlineStrong, Color.chHairline.opacity(0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    }
                    .shadow(color: shadow, radius: 11, y: 4)
            }
    }
}

extension View {
    func glassPanel(
        radius: CGFloat = CHRadius.card,
        surface: Color = .chSurfaceCard,
        shadow: Color = .chShadowCard
    ) -> some View {
        modifier(GlassPanelModifier(radius: radius, surface: surface, shadow: shadow))
    }
}

/// Window backdrop: warm gradient, three glowing color blobs, halftone dot texture.
/// The glass panels above blur these blobs — that's the whole liquid-glass effect.
struct WindowBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: .chBg1, location: 0),
                        .init(color: .chBg2, location: 0.55),
                        .init(color: .chBg3, location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                blob(.chBlobTerracotta, diameter: 460)
                    .position(x: 150, y: 330)
                blob(.chBlobAmber, diameter: 420)
                    .position(x: geo.size.width - 150, y: 130)
                blob(.chBlobSage, diameter: 480)
                    .position(x: geo.size.width - 500, y: geo.size.height - 120)
                HalftoneTexture()
            }
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, diameter: CGFloat) -> some View {
        RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: diameter / 2)
            .frame(width: diameter, height: diameter)
    }
}

/// Halftone dot grid (1px dots on a 9px grid), from tokens/surfaces.css.
struct HalftoneTexture: View {
    var body: some View {
        // ponytail: O(w·h/81) dots per redraw; switch to a tiled image if resize ever stutters
        Canvas { ctx, size in
            let step: CGFloat = 9
            var dotY: CGFloat = 4
            while dotY < size.height {
                var dotX: CGFloat = 4
                while dotX < size.width {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: dotX, y: dotY, width: 2, height: 2)),
                        with: .color(.chHalftoneDot)
                    )
                    dotX += step
                }
                dotY += step
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        WindowBackdrop()
        Text("Frosted panel")
            .font(CHType.cardTitle)
            .foregroundStyle(Color.chTextTitle)
            .padding(24)
            .glassPanel()
    }
    .frame(width: 600, height: 400)
}
