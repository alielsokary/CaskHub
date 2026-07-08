//
//  BarrelMark.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

/// The CaskHub barrel mascot (identity v2, design option 3a) — terracotta barrel
/// with staves, riveted gold hoops and a shine. Ported from the design system's
/// BarrelMark SVG (48×48 viewBox); scales to any square frame.
struct BarrelMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 48
            ctx.translateBy(x: (size.width - 48 * s) / 2, y: (size.height - 48 * s) / 2)
            ctx.scaleBy(x: s, y: s)

            let outline = Color.chBarrelOutline

            // Barrel body
            var barrel = Path()
            barrel.move(to: CGPoint(x: 24, y: 4.5))
            barrel.addCurve(to: CGPoint(x: 39.7, y: 13.5), control1: CGPoint(x: 33, y: 4.5), control2: CGPoint(x: 38.6, y: 6.4))
            barrel.addCurve(to: CGPoint(x: 39.7, y: 34.5), control1: CGPoint(x: 40.8, y: 20), control2: CGPoint(x: 40.8, y: 28))
            barrel.addCurve(to: CGPoint(x: 24, y: 43.5), control1: CGPoint(x: 38.6, y: 41.6), control2: CGPoint(x: 33, y: 43.5))
            barrel.addCurve(to: CGPoint(x: 8.3, y: 34.5), control1: CGPoint(x: 15, y: 43.5), control2: CGPoint(x: 9.4, y: 41.6))
            barrel.addCurve(to: CGPoint(x: 8.3, y: 13.5), control1: CGPoint(x: 7.2, y: 28), control2: CGPoint(x: 7.2, y: 20))
            barrel.addCurve(to: CGPoint(x: 24, y: 4.5), control1: CGPoint(x: 9.4, y: 6.4), control2: CGPoint(x: 15, y: 4.5))
            barrel.closeSubpath()
            ctx.fill(barrel, with: .color(.chTerracotta))
            ctx.stroke(barrel, with: .color(outline), lineWidth: 2.6)

            // Lid
            let lid = Path(ellipseIn: CGRect(x: 13.5, y: 5.9, width: 21, height: 5.4))
            ctx.fill(lid, with: .color(.chTerracottaLid))
            ctx.stroke(lid, with: .color(outline), lineWidth: 1.8)

            // Staves
            var staves = Path()
            staves.move(to: CGPoint(x: 24, y: 5.2))
            staves.addLine(to: CGPoint(x: 24, y: 42.8))
            staves.move(to: CGPoint(x: 14.5, y: 6.2))
            staves.addCurve(to: CGPoint(x: 14.5, y: 41.8), control1: CGPoint(x: 11.3, y: 17.7), control2: CGPoint(x: 11.3, y: 30.2))
            staves.move(to: CGPoint(x: 33.5, y: 6.2))
            staves.addCurve(to: CGPoint(x: 33.5, y: 41.8), control1: CGPoint(x: 36.7, y: 17.7), control2: CGPoint(x: 36.7, y: 30.2))
            ctx.stroke(staves, with: .color(outline), lineWidth: 1.5)

            // Hoops — ink underlay + gold band
            var hoopTop = Path()
            hoopTop.move(to: CGPoint(x: 11.8, y: 16.4))
            hoopTop.addQuadCurve(to: CGPoint(x: 36.2, y: 16.4), control: CGPoint(x: 24, y: 18.2))
            var hoopBottom = Path()
            hoopBottom.move(to: CGPoint(x: 11.4, y: 31.9))
            hoopBottom.addQuadCurve(to: CGPoint(x: 36.6, y: 31.9), control: CGPoint(x: 24, y: 34.9))
            for hoop in [hoopTop, hoopBottom] {
                ctx.stroke(hoop, with: .color(outline), style: StrokeStyle(lineWidth: 7.8, lineCap: .round))
                ctx.stroke(hoop, with: .color(.chGoldBand), style: StrokeStyle(lineWidth: 4.2, lineCap: .round))
            }

            // Rivets
            let rivets: [CGPoint] = [
                CGPoint(x: 12, y: 16.5), CGPoint(x: 24, y: 17.3), CGPoint(x: 36, y: 16.5),
                CGPoint(x: 12, y: 32.2), CGPoint(x: 24, y: 33.4), CGPoint(x: 36, y: 32.2),
            ]
            for p in rivets {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.3, y: p.y - 1.3, width: 2.6, height: 2.6)), with: .color(.chInk))
            }

            // Shine
            var shine = Path()
            shine.move(to: CGPoint(x: 9.6, y: 22))
            shine.addCurve(to: CGPoint(x: 9.4, y: 25.6), control1: CGPoint(x: 9.3, y: 23.2), control2: CGPoint(x: 9.2, y: 24.4))
            shine.move(to: CGPoint(x: 11.2, y: 36.8))
            shine.addCurve(to: CGPoint(x: 11.9, y: 38.2), control1: CGPoint(x: 11.4, y: 37.3), control2: CGPoint(x: 11.6, y: 37.8))
            ctx.stroke(shine, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
        }
    }
}

/// "caskhub" wordmark: barrel + Baloo 2 lettering with terracotta "hub".
struct BrandWordmark: View {
    var body: some View {
        HStack(spacing: 9) {
            BarrelMark()
                .frame(width: 30, height: 30)
            HStack(spacing: 0) {
                Text("cask").foregroundStyle(Color.chTextTitle)
                Text("hub").foregroundStyle(Color.chTextBrand)
            }
            .font(CHType.wordmark)
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        BarrelMark().frame(width: 120, height: 120)
        BrandWordmark()
    }
    .padding(40)
    .background(Color.chCream)
}
