//
//  CaskActionsView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

private struct AdoptPageKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the Adopt Apps library page is showing — the only place the Adopt button lives.
    var isAdoptPage: Bool {
        get { self[AdoptPageKey.self] }
        set { self[AdoptPageKey.self] = newValue }
    }
}

struct CaskActionsView: View {
    let cask: Cask
    var fullWidth = true
    var onUninstall: (() -> Void)?

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @Environment(\.isAdoptPage) private var isAdoptPage

    var body: some View {
        if let inFlight = localHomebrew.inFlightActions[cask.token] {
            inFlightCapsule(for: inFlight)
        } else if let installation = localHomebrew.installedCasks[cask.token] {
            installedActions(for: installation)
        } else if localHomebrew.isAdoptable(cask) {
            HStack(spacing: 8) {
                if isAdoptPage {
                    ActionCapsuleButton(action: .adopt, fullWidth: fullWidth) {
                        Task { try? await localHomebrew.adopt(token: cask.token) }
                    }
                } else {
                    ActionCapsuleButton(action: .open, fullWidth: fullWidth) {
                        localHomebrew.openExternalApp(cask: cask)
                    }
                }
                disabledUninstallHint
            }
        } else {
            ActionCapsuleButton(action: .install, fullWidth: fullWidth) {
                Task { try? await localHomebrew.install(token: cask.token) }
            }
        }
    }

    /// Plain image, not a disabled Button — macOS suppresses tooltips on disabled controls.
    private var disabledUninstallHint: some View {
        Image(systemName: "trash")
            .font(.caption)
            .foregroundStyle(Color.chTextFaint)
            .padding(7)
            .background(Circle().fill(Color.chSurfaceField.opacity(0.5)))
            .overlay(Circle().strokeBorder(Color.chHairline, lineWidth: 1))
            .help("Adopt this app first so CaskHub can manage/uninstall it.")
    }

    @ViewBuilder
    private func installedActions(for installation: LocalCaskInstallation) -> some View {
        let showUpdate = localHomebrew.hasAvailableUpdate(
            token: cask.token, remoteVersion: cask.version, autoUpdates: cask.autoUpdates
        )
        let canOpen = !installation.appBundleNames.isEmpty

        HStack(spacing: 8) {
            if canOpen {
                ActionCapsuleButton(action: .open, fullWidth: fullWidth && !showUpdate) {
                    localHomebrew.openApp(token: cask.token)
                }
            }
            if showUpdate {
                ActionCapsuleButton(action: .update, fullWidth: fullWidth) {
                    Task { try? await localHomebrew.upgrade(token: cask.token) }
                }
            }
            if !canOpen && !showUpdate {
                ActionCapsuleLabel(action: .installed, fullWidth: fullWidth)
            }
            if let onUninstall {
                if !fullWidth { Spacer(minLength: 0) }
                Button(action: onUninstall) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(Color.chTextBody)
                        .padding(7)
                        .background(Circle().fill(Color.chSurfaceField))
                        .overlay(Circle().strokeBorder(Color.chHairline, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func inFlightCapsule(for action: CaskAction) -> some View {
        let token = cask.token
        let isCanceling = localHomebrew.cancelRequested.contains(token)
        let canCancel = localHomebrew.cancellableDownloads.contains(token) && !isCanceling
        let label = isCanceling
            ? "Canceling…"
            : (canCancel ? "Downloading…" : action.inProgressLabel)

        return HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(label)
                .font(CHType.bodySm)
                .foregroundStyle(Color.chTextBody)
            if canCancel {
                Spacer(minLength: 0)
                Button {
                    localHomebrew.cancelInstall(token: token)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.chTextBody)
                        .padding(4)
                        .background(Circle().fill(Color.chSurfaceField))
                        .overlay(Circle().strokeBorder(Color.chHairline, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Cancel download")
            }
        }
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .padding(.vertical, 5)
        .padding(.horizontal, 16)
        .background(Capsule().fill(Color.chSurfaceField))
        .overlay(Capsule().strokeBorder(Color.chHairline, lineWidth: 1))
    }
}
