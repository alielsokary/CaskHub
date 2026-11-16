//
//  GlassPanel.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

private struct GlassPanelModifier: ViewModifier {
    var radius: CGFloat
    var surface: Color
    var shadow: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if CHType.isNative {
            content.background { NativeCardSurface(shape: shape, fill: surface) }
        } else {
            classic(content, shape: shape)
        }
    }

    private func classic(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background {
                shape
                    .fill(surface)
                    .background(.ultraThinMaterial, in: shape)
                    .overlay {
                        LinearGradient(
                            colors: [Color.chHairlineStrong, Color.chHairline.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .mask(shape.strokeBorder(lineWidth: 1))
                    }
                    .shadow(color: shadow, radius: 11, y: 4)
            }
    }
}

struct ScrolledUnderToolbarKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct ToolbarScrollEdge: ViewModifier {
    @State private var isScrolled = false

    func body(content: Content) -> some View {
        edgeEffect(content)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 0.5
            } action: { _, scrolled in
                isScrolled = scrolled
            }
            .preference(key: ScrolledUnderToolbarKey.self, value: isScrolled)
    }

    @ViewBuilder
    private func edgeEffect(_ content: Content) -> some View {
        if #available(macOS 26, *) {
            content.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
        }
    }
}

private struct NativeCardSurface: View {
    let shape: RoundedRectangle
    let fill: Color

    var body: some View {
        shape
            .fill(fill)
            // A gradient-styled stroke rasterizes on the CPU per card; a masked gradient view composites on the GPU.
            .overlay {
                LinearGradient(
                    colors: [Color.chNativeCardHighlight, .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.08)
                )
                .mask(shape.strokeBorder(lineWidth: 1))
            }
            .overlay { shape.stroke(Color.chNativeCardEdge, lineWidth: 0.5) }
            .shadow(color: Color.chNativeCardShadow, radius: 1.5, y: 1)
    }
}

extension View {
    func toolbarScrollEdge() -> some View {
        modifier(ToolbarScrollEdge())
    }

    func glassPanel(
        radius: CGFloat = CHRadius.card,
        surface: Color = .chSurfaceCard,
        shadow: Color = .chShadowCard
    ) -> some View {
        modifier(GlassPanelModifier(radius: radius, surface: surface, shadow: shadow))
    }
}

struct WindowBackdrop: View {
    var body: some View {
        if CHType.isNative {
            Color.chNativeWindow.ignoresSafeArea()
        } else {
            classic
        }
    }

    private var classic: some View {
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

struct HalftoneTexture: View {
    var color: Color = .chHalftoneDot
    var step: CGFloat = 9
    var dot: CGFloat = 2

    var body: some View {
        // ponytail: O(w·h/step²) dots per redraw; switch to a tiled image if resize ever stutters
        Canvas { ctx, size in
            let start = (step - 1) / 2
            var dotY = start
            while dotY < size.height {
                var dotX = start
                while dotX < size.width {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: dotX, y: dotY, width: dot, height: dot)),
                        with: .color(color)
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
