//
//  StatusBarView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

struct StatusBarView: View {
    var caskCount: Int
    var brewVersion: String?
    var caskFlowRelease: String?

    var body: some View {
        HStack(spacing: 16) {
            BarrelMark()
                .frame(width: 16, height: 16)

            Text(statusLine)
                .font(CHType.statusMono)
                .foregroundStyle(Color.chTextBody)

            Spacer()

            HStack(spacing: 5) {
                Keycap(symbol: "⌘F")
                Text("search")
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextBody)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background {
            Rectangle()
                .fill(Color.chSurfaceStatusbar)
                .background(.ultraThinMaterial)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.chHairline).frame(height: 1)
        }
    }

    private var statusLine: String {
        var parts: [String] = []
        if let brewVersion { parts.append("brew \(brewVersion)") }
        parts.append("tap homebrew/cask")
        if caskCount > 0 { parts.append("\(caskCount.formatted()) casks") }
        if let caskFlowRelease { parts.append(caskFlowRelease) }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        WindowBackdrop()
        StatusBarView(caskCount: 3781, caskFlowRelease: "caskflow-v2026.07.10")
    }
    .frame(width: 700, height: 200)
}
