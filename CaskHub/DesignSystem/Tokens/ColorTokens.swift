//
//  ColorTokens.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

// CaskHub color tokens — ported from the design system (tokens/colors.css).
// Light values = design option 3b, dark values = option 3c.

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

private func adaptive(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}

extension Color {
    // ── Base palette (fixed) ──────────────────────────
    static let chCream = Color(nsColor: NSColor(hex: 0xF6E9CB))
    static let chInk = Color(nsColor: NSColor(hex: 0x33304A))
    static let chTerracotta = Color(nsColor: NSColor(hex: 0xC8674A))
    static let chTerracottaLid = Color(nsColor: NSColor(hex: 0xA94F36))
    static let chSage = Color(nsColor: NSColor(hex: 0x6FA287))
    static let chAmber = Color(nsColor: NSColor(hex: 0xD99A4E))
    static let chGoldBand = Color(nsColor: NSColor(hex: 0xF0D59A))

    // ── Window background gradient stops ──────────────
    static let chBg1 = adaptive(light: NSColor(hex: 0xF2E2BD), dark: NSColor(hex: 0x232030))
    static let chBg2 = adaptive(light: NSColor(hex: 0xF8EED8), dark: NSColor(hex: 0x2E2A40))
    static let chBg3 = adaptive(light: NSColor(hex: 0xF3E6C6), dark: NSColor(hex: 0x262234))

    // ── Glass surfaces ─────────────────────────────────
    static let chSurfaceSidebar = adaptive(light: NSColor(hex: 0xFDF6E4, alpha: 0.80), dark: NSColor(hex: 0x242132, alpha: 0.88))
    static let chSurfaceToolbar = adaptive(light: NSColor(hex: 0xFDF6E4, alpha: 0.82), dark: NSColor(hex: 0x353147, alpha: 0.85))
    static let chSurfaceCard = adaptive(light: NSColor(hex: 0xFDF6E4, alpha: 0.80), dark: NSColor(hex: 0x353147, alpha: 0.85))
    static let chSurfaceHero = adaptive(light: NSColor(hex: 0xFDF6E4, alpha: 0.78), dark: NSColor(hex: 0x3A3450, alpha: 0.85))
    static let chSurfaceStatusbar = adaptive(light: NSColor(hex: 0xEFDCB2, alpha: 0.85), dark: NSColor(hex: 0x242132, alpha: 0.90))
    static let chSurfaceField = adaptive(light: NSColor(hex: 0xFFFFFF, alpha: 0.50), dark: NSColor(hex: 0xFFFFFF, alpha: 0.08))
    static let chSurfaceKeycap = adaptive(light: NSColor(hex: 0xFFFFFF, alpha: 0.55), dark: NSColor(hex: 0xFFFFFF, alpha: 0.12))

    // ── Hairlines & separators ─────────────────────────
    static let chHairline = adaptive(light: NSColor(hex: 0xFFFFFF, alpha: 0.75), dark: NSColor(hex: 0xFFFFFF, alpha: 0.14))
    static let chHairlineStrong = adaptive(light: NSColor(hex: 0xFFFFFF, alpha: 0.90), dark: NSColor(hex: 0xFFFFFF, alpha: 0.22))
    static let chSeparator = adaptive(light: NSColor(hex: 0x33304A, alpha: 0.18), dark: NSColor(hex: 0xF6E9CB, alpha: 0.12))

    // ── Text ───────────────────────────────────────────
    static let chTextTitle = adaptive(light: NSColor(hex: 0x33304A), dark: NSColor(hex: 0xF6E9CB))
    static let chTextBody = adaptive(light: NSColor(hex: 0x6B6252), dark: NSColor(hex: 0xB3ACC5))
    static let chTextNav = adaptive(light: NSColor(hex: 0x5A5344), dark: NSColor(hex: 0xC5BFD4))
    static let chTextMuted = adaptive(light: NSColor(hex: 0xA08D63), dark: NSColor(hex: 0x8D87A0))
    static let chTextFaint = adaptive(light: NSColor(hex: 0xB3A074), dark: NSColor(hex: 0x6A6380))
    static let chTextBrand = adaptive(light: NSColor(hex: 0xC8674A), dark: NSColor(hex: 0xE0876A))

    // ── Action colors (tonal liquid-glass capsules) ────
    static let chActionInstallBg = adaptive(light: NSColor(hex: 0xC8674A, alpha: 0.22), dark: NSColor(hex: 0xE0876A, alpha: 0.16))
    static let chActionInstallBorder = adaptive(light: NSColor(hex: 0xC8674A, alpha: 0.55), dark: NSColor(hex: 0xE0876A, alpha: 0.45))
    static let chActionInstallFg = adaptive(light: NSColor(hex: 0x9C4A2B), dark: NSColor(hex: 0xF0A284))
    static let chActionUpdateBg = adaptive(light: NSColor(hex: 0xD99A4E, alpha: 0.28), dark: NSColor(hex: 0xE2AB60, alpha: 0.18))
    static let chActionUpdateBorder = adaptive(light: NSColor(hex: 0xD99A4E, alpha: 0.60), dark: NSColor(hex: 0xE2AB60, alpha: 0.50))
    static let chActionUpdateFg = adaptive(light: NSColor(hex: 0x8A5A1A), dark: NSColor(hex: 0xECC084))
    static let chActionDoneBg = adaptive(light: NSColor(hex: 0x6FA287, alpha: 0.25), dark: NSColor(hex: 0x6FA287, alpha: 0.20))
    static let chActionDoneBorder = adaptive(light: NSColor(hex: 0x6FA287, alpha: 0.60), dark: NSColor(hex: 0x6FA287, alpha: 0.50))
    static let chActionDoneFg = adaptive(light: NSColor(hex: 0x3E6E55), dark: NSColor(hex: 0x8FC4A8))

    // ── Segmented view-mode toggle ─────────────────────
    // Selected segment: ink capsule + cream glyph in light; cream capsule + ink glyph in dark.
    static let chSegmentIcon = adaptive(light: NSColor(hex: 0xFDF6E4), dark: NSColor(hex: 0x2B2838))

    // ── Badge ──────────────────────────────────────────
    static let chBadgeBg = adaptive(light: NSColor(hex: 0xD99A4E, alpha: 0.35), dark: NSColor(hex: 0xE2AB60, alpha: 0.28))
    static let chBadgeBorder = adaptive(light: NSColor(hex: 0xFFFFFF, alpha: 0.80), dark: NSColor(hex: 0xFFFFFF, alpha: 0.30))
    static let chBadgeFg = adaptive(light: NSColor(hex: 0x8A5A1A), dark: NSColor(hex: 0xECC084))

    // ── Decorative blob glows (behind glass panels) ────
    static let chBlobTerracotta = adaptive(light: NSColor(hex: 0xC8674A, alpha: 0.38), dark: NSColor(hex: 0xC8674A, alpha: 0.35))
    static let chBlobAmber = adaptive(light: NSColor(hex: 0xD99A4E, alpha: 0.40), dark: NSColor(hex: 0xD99A4E, alpha: 0.28))
    static let chBlobSage = adaptive(light: NSColor(hex: 0x6FA287, alpha: 0.35), dark: NSColor(hex: 0x6FA287, alpha: 0.26))

    // ── Textures & shadows ─────────────────────────────
    static let chHalftoneDot = adaptive(light: NSColor(hex: 0x33304A, alpha: 0.05), dark: NSColor(hex: 0xF6E9CB, alpha: 0.045))
    static let chShadowCard = adaptive(light: NSColor(hex: 0x33304A, alpha: 0.10), dark: NSColor(hex: 0x000000, alpha: 0.28))
    static let chShadowHero = adaptive(light: NSColor(hex: 0x33304A, alpha: 0.12), dark: NSColor(hex: 0x000000, alpha: 0.35))

    // ── Barrel mark ────────────────────────────────────
    static let chBarrelOutline = adaptive(light: NSColor(hex: 0x33304A), dark: NSColor(hex: 0xF6E9CB))
}
