//
//  Controls.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

enum CaskActionStyle {
    case install, adopt, update, open, installed, cleanup

    var title: String {
        switch self {
        case .install: return "Install"
        case .adopt: return "Adopt"
        case .update: return "Update"
        case .open: return "Open"
        case .installed: return "Installed"
        case .cleanup: return "Clean Up"
        }
    }

    var icon: String {
        switch self {
        case .install: return "arrow.down"
        case .adopt: return "tray.and.arrow.down"
        case .update: return "arrow.clockwise"
        case .open: return "play.fill"
        case .installed: return "circle.fill"
        case .cleanup: return "trash"
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .installed: return 6.5
        case .open: return 9
        case .install, .adopt, .update, .cleanup: return 10.5
        }
    }

    var background: Color {
        switch self {
        case .install, .adopt: return .chActionInstallBg
        case .update, .cleanup: return .chActionUpdateBg
        case .open, .installed: return .chActionDoneBg
        }
    }

    var border: Color {
        switch self {
        case .install, .adopt: return .chActionInstallBorder
        case .update, .cleanup: return .chActionUpdateBorder
        case .open, .installed: return .chActionDoneBorder
        }
    }

    var foreground: Color {
        switch self {
        case .install, .adopt: return .chActionInstallFg
        case .update, .cleanup: return .chActionUpdateFg
        case .open, .installed: return .chActionDoneFg
        }
    }
}

struct ActionCapsuleLabel: View {
    let action: CaskActionStyle
    var fullWidth = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: action.icon)
                .font(.system(size: action.iconSize, weight: .bold))
            Text(action.title)
                .font(CHType.button)
        }
        .foregroundStyle(action.foreground)
        .lineLimit(1)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .frame(height: CHSize.actionCapsuleHeight)
        .padding(.horizontal, fullWidth ? 4 : 22)
        .background(Capsule().fill(action.background))
        .overlay(Capsule().strokeBorder(action.border, lineWidth: 1))
    }
}

struct ActionCapsuleButton: View {
    let action: CaskActionStyle
    var fullWidth = true
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ActionCapsuleLabel(action: action, fullWidth: fullWidth)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(CHType.label)
            .foregroundStyle(Color.chBadgeFg)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(Color.chBadgeBg))
            .overlay(Capsule().strokeBorder(Color.chBadgeBorder, lineWidth: 1))
    }
}

struct Keycap: View {
    let symbol: String

    var body: some View {
        content
            .foregroundStyle(Color.chTextTitle)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: CHRadius.keycap).fill(Color.chSurfaceKeycap))
            .overlay(RoundedRectangle(cornerRadius: CHRadius.keycap).strokeBorder(Color.chHairlineStrong, lineWidth: 1))
            .shadow(color: Color.chShadowCard, radius: 2, y: 1)
    }

    @ViewBuilder
    private var content: some View {
        if symbol.hasPrefix("⌘") {
            HStack(spacing: 1) {
                Image(systemName: "command")
                    .font(.system(size: 8.5, weight: .bold))
                Text(symbol.dropFirst())
                    .font(CHType.keycap)
            }
        } else {
            Text(symbol)
                .font(CHType.keycap)
        }
    }
}

#Preview {
    ZStack {
        WindowBackdrop()
        VStack(spacing: 14) {
            ActionCapsuleButton(action: .install, fullWidth: false) {}
            ActionCapsuleButton(action: .update, fullWidth: false) {}
            ActionCapsuleButton(action: .open, fullWidth: false) {}
            ActionCapsuleLabel(action: .installed, fullWidth: false)
            HStack { CountBadge(count: 3); Keycap(symbol: "⌘K") }
        }
        .padding(40)
    }
    .frame(width: 320, height: 340)
}
