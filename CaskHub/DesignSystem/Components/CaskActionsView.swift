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
        } else if localHomebrew.installedCasks[cask.token] != nil {
            installedActions
        } else if localHomebrew.isAdoptable(cask) {
            HStack(spacing: 8) {
                if isAdoptPage {
                    ActionCapsuleButton(action: .adopt, fullWidth: fullWidth) {
                        if localHomebrew.isExternalPackageInstalled(cask) {
                            localHomebrew.requestPackageAdoption(token: cask.token)
                        } else {
                            Task { try? await localHomebrew.adopt(cask) }
                        }
                    }
                } else {
                    ActionCapsuleButton(action: .open, fullWidth: fullWidth) {
                        localHomebrew.openExternalApp(cask: cask)
                    }
                }
                DisabledUninstallControl(
                    message: "Adopt this app first so CaskHub can manage/uninstall it."
                )
            }
        } else if localHomebrew.isMacAppStoreInstalled(cask) {
            HStack(spacing: 8) {
                ActionCapsuleButton(action: .open, fullWidth: fullWidth) {
                    localHomebrew.openExternalApp(cask: cask)
                }
                DisabledUninstallControl(
                    message: "Installed from the Mac App Store. Uninstall it from Finder or Launchpad."
                )
            }
        } else if let externalPath = localHomebrew.externalCLIPath(cask) {
            ActionCapsuleLabel(action: .installed, fullWidth: fullWidth)
                .help(
                    "Installed outside Homebrew at \(externalPath.path). "
                        + "Remove or move that file manually before installing the Homebrew version."
                )
        } else {
            ActionCapsuleButton(action: .install, fullWidth: fullWidth) {
                Task { try? await localHomebrew.install(token: cask.token) }
            }
        }
    }

    @ViewBuilder
    private var installedActions: some View {
        if localHomebrew.isZombie(cask) {
            ActionCapsuleButton(action: .cleanup, fullWidth: fullWidth) {
                Task { try? await localHomebrew.repair(token: cask.token) }
            }
            .help("""
            \(cask.displayName) was removed outside Homebrew, but Homebrew still \
            has records for it. Clean Up removes the leftover data.
            """)
        } else {
            managedActions
        }
    }

    @ViewBuilder
    private var managedActions: some View {
        let showUpdate = localHomebrew.hasAvailableUpdate(
            token: cask.token, remoteVersion: cask.version, autoUpdates: cask.autoUpdates
        )
        let canOpen = localHomebrew.canOpen(cask)

        HStack(spacing: 8) {
            if canOpen {
                ActionCapsuleButton(action: .open, fullWidth: fullWidth && !showUpdate) {
                    localHomebrew.open(cask)
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

        return CaskOperationCapsule(
            action: action,
            progress: localHomebrew.operationProgress[token],
            isCanceling: isCanceling,
            canCancel: canCancel,
            fullWidth: fullWidth,
            onCancel: { localHomebrew.cancelInstall(token: token) }
        )
    }
}

/// SwiftUI's native `.help` tooltip is dismissed by a click even while the
/// pointer remains over the view. This hint follows hover state directly, so it
/// stays visible until the pointer actually leaves the disabled control.
private struct DisabledUninstallControl: View {
    let message: String

    @State private var isHovering = false

    var body: some View {
        Image(systemName: "trash")
            .font(.caption)
            .foregroundStyle(Color.chTextFaint)
            .padding(7)
            .background(Circle().fill(Color.chSurfaceField.opacity(0.5)))
            .overlay(Circle().strokeBorder(Color.chHairline, lineWidth: 1))
            .contentShape(Circle())
            .onHover { isHovering = $0 }
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Text(message)
                        .font(CHType.bodySm)
                        .foregroundStyle(Color.chTextTitle)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 220, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.chSurfaceToolbar)
                                .shadow(color: Color.chShadowCard, radius: 8, y: 3)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.chHairlineStrong, lineWidth: 1)
                        )
                        .offset(y: -48)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(isHovering ? 10 : 0)
            .accessibilityLabel("Uninstall")
            .accessibilityHint(message)
    }
}
