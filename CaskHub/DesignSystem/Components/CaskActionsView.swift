//
//  CaskActionsView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import SwiftUI

struct CaskActionsView: View {
    let cask: Cask
    var fullWidth = true
    var onUninstall: (() -> Void)?

    @Environment(LocalHomebrewService.self) private var localHomebrew

    var body: some View {
        if let inFlight = localHomebrew.inFlightActions[cask.token] {
            inFlightCapsule(for: inFlight)
        } else if let installation = localHomebrew.installedCasks[cask.token] {
            installedActions(for: installation)
        } else {
            ActionCapsuleButton(action: .install, fullWidth: fullWidth) {
                Task { try? await localHomebrew.install(token: cask.token) }
            }
        }
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
