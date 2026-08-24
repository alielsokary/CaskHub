//
//  CaskOperationCapsule.swift
//  CaskHub
//
//  Created by Ali Elsokary on 24/07/2026.
//

import SwiftUI

struct CaskOperationCapsule: View {
    let action: CaskAction
    let progress: CaskOperationProgress?
    let isCanceling: Bool
    let canCancel: Bool
    let fullWidth: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if showsDownloadIcon {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accentColor)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            if let byteProgress = downloadByteProgress {
                Text(progress?.phase.label(for: action) ?? "Downloading")
                    .font(CHType.downloadLabel)
                    .foregroundStyle(Color.chTextBody)
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 6)

                Text(byteProgress.text)
                    .font(CHType.downloadProgress)
                    .monospacedDigit()
                    .foregroundStyle(Color.chTextBody)
                    .lineLimit(1)
            } else {
                Text(label)
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextBody)
                    .lineLimit(1)
            }

            if canCancel {
                if downloadByteProgress == nil {
                    Spacer(minLength: 0)
                }
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.chTextBody)
                        .padding(4)
                        .background(Circle().fill(Color.chSurfaceField))
                        .overlay(Circle().strokeBorder(Color.chHairline, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Cancel operation")
            }
        }
        .frame(
            minWidth: fullWidth ? nil : 200,
            maxWidth: fullWidth ? .infinity : nil
        )
        .frame(height: CHSize.actionCapsuleHeight)
        .padding(.horizontal, 12)
        .background {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.chSurfaceField)
                if let fractionCompleted {
                    SmoothProgressFill(
                        fraction: fractionCompleted,
                        color: accentColor.opacity(0.18)
                    )
                } else if showsIndeterminateDownloadFill {
                    IndeterminateProgressFill(color: accentColor.opacity(0.18))
                }
            }
        }
        .overlay(Capsule().strokeBorder(Color.chHairline, lineWidth: 1))
        .accessibilityLabel(label.replacingOccurrences(of: " · ", with: ", "))
    }

    private var downloadByteProgress: CaskByteProgress? {
        guard !isCanceling, progress?.phase.showsByteProgress == true else { return nil }
        return progress?.byteProgress
    }

    private var label: String {
        if isCanceling {
            return String(localized: "Canceling…")
        }
        return progress?.inlineLabel ?? action.inProgressLabel
    }

    private var fractionCompleted: Double? {
        guard !isCanceling, progress?.phase.showsByteProgress == true else { return nil }
        return progress?.fractionCompleted
    }

    private var showsDownloadIcon: Bool {
        !isCanceling && progress?.phase.isDownloadActivity == true
    }

    private var showsIndeterminateDownloadFill: Bool {
        showsDownloadIcon && fractionCompleted == nil
    }

    private var accentColor: Color {
        switch action {
        case .updating, .updatingHomebrew:
            return .chActionUpdateFg
        case .installing, .adopting, .repairing:
            return .chActionInstallFg
        default:
            return .chTextBrand
        }
    }
}

private struct IndeterminateProgressFill: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width * 0.34, 24)

            Capsule()
                .fill(color)
                .frame(width: width)
                .offset(
                    x: reduceMotion
                        ? 0
                        : (isAnimating ? proxy.size.width : -width)
                )
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                        isAnimating = true
                    }
                }
        }
        .clipShape(Capsule())
    }
}

private struct SmoothProgressFill: View {
    let fraction: Double
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedFraction: Double

    init(fraction: Double, color: Color) {
        self.fraction = fraction
        self.color = color
        _displayedFraction = State(initialValue: fraction)
    }

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(color)
                .frame(width: proxy.size.width * displayedFraction)
        }
        .clipShape(Capsule())
        .onChange(of: fraction) { _, newValue in
            if reduceMotion {
                displayedFraction = newValue
            } else {
                withAnimation(.linear(duration: 0.20)) {
                    displayedFraction = newValue
                }
            }
        }
    }
}
