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
    var operation: CaskOperationStatus?

    var body: some View {
        HStack(spacing: 16) {
            BarrelMark()
                .frame(width: 16, height: 16)

            Text(statusLine)
                .font(CHType.statusMono)
                .foregroundStyle(Color.chTextBody)

            if let operation {
                operationView(operation)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

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
        .animation(.snappy(duration: 0.28), value: operation != nil)
    }

    private func operationView(_ operation: CaskOperationStatus) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.chHairlineStrong)
                .frame(width: 1, height: 13)

            ProgressView()
                .controlSize(.mini)
                .tint(Color.chTextBrand)

            Text(operation.message)
                .font(CHType.statusMono)
                .monospacedDigit()
                .foregroundStyle(Color.chTextBody)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(operation.message)
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
        StatusBarView(
            caskCount: 3781,
            caskFlowRelease: "caskflow-v2026.07.10",
            operation: CaskOperationStatus(
                label: "Downloading Docker Desktop",
                byteProgress: CaskByteProgress(
                    completedBytes: 84_000_000,
                    totalBytes: 245_000_000
                )
            )
        )
    }
    .frame(width: 700, height: 200)
}
