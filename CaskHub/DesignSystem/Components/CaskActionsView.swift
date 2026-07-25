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
    var localState: CaskLocalState?
    var fullWidth = true
    var onUninstall: (() -> Void)?
    var showsUninstallControl = true
    var usesIconOnlyOpenAndUpdate = false

    @Environment(LocalHomebrewService.self) private var localHomebrew
    @Environment(\.isAdoptPage) private var isAdoptPage

    var body: some View {
        let state = localState ?? localHomebrew.localState(for: cask)
        if let inFlight = localHomebrew.inFlightActions[cask.token] {
            inFlightCapsule(for: inFlight)
        } else if state.isHomebrewInstalled {
            installedActions(state)
        } else if state.isAdoptable {
            HStack(spacing: 8) {
                if isAdoptPage {
                    ActionCapsuleButton(action: .adopt, fullWidth: fullWidth) {
                        if state.isExternalPackage {
                            localHomebrew.requestPackageAdoption(token: cask.token)
                        } else {
                            Task { try? await localHomebrew.adopt(cask) }
                        }
                    }
                } else {
                    openButton(fullWidth: fullWidth) {
                        localHomebrew.openExternalApp(cask: cask)
                    }
                }
                if showsUninstallControl,
                   let reason = state.uninstallAvailability.unavailableReason {
                    DisabledUninstallControl(message: reason)
                }
            }
        } else if state.installationSource == .macAppStore {
            HStack(spacing: 8) {
                openButton(fullWidth: fullWidth) {
                    localHomebrew.openExternalApp(cask: cask)
                }
                if showsUninstallControl,
                   let reason = state.uninstallAvailability.unavailableReason {
                    DisabledUninstallControl(message: reason)
                }
            }
        } else if let externalPath = state.externalCLIPath {
            ActionCapsuleLabel(action: .installed, fullWidth: fullWidth)
                .help(
                    state.uninstallAvailability.unavailableReason
                        ?? "Installed outside Homebrew at \(externalPath.path)."
                )
        } else {
            ActionCapsuleButton(action: .install, fullWidth: fullWidth) {
                Task { try? await localHomebrew.install(token: cask.token) }
            }
        }
    }

    @ViewBuilder
    private func installedActions(_ state: CaskLocalState) -> some View {
        if state.isZombie {
            ActionCapsuleButton(action: .cleanup, fullWidth: fullWidth) {
                Task { try? await localHomebrew.repair(token: cask.token) }
            }
            .help("""
            \(cask.displayName) was removed outside Homebrew, but Homebrew still \
            has records for it. Clean Up removes the leftover data.
            """)
        } else {
            managedActions(state)
        }
    }

    @ViewBuilder
    private func managedActions(_ state: CaskLocalState) -> some View {
        HStack(spacing: 8) {
            if state.canOpen {
                openButton(
                    fullWidth: fullWidth && !state.hasAvailableUpdate,
                    isPairedWithUpdate: state.hasAvailableUpdate
                ) {
                    localHomebrew.open(cask)
                }
            }
            if state.hasAvailableUpdate {
                updateButton(fullWidth: fullWidth) {
                    Task { try? await localHomebrew.upgrade(token: cask.token) }
                }
            }
            if !state.canOpen && !state.hasAvailableUpdate {
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

    @ViewBuilder
    private func openButton(
        fullWidth: Bool,
        isPairedWithUpdate: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if usesIconOnlyOpenAndUpdate && isPairedWithUpdate {
            ActionCapsuleIconButton(action: .open, onTap: action)
        } else {
            ActionCapsuleButton(action: .open, fullWidth: fullWidth, onTap: action)
        }
    }

    @ViewBuilder
    private func updateButton(fullWidth: Bool, action: @escaping () -> Void) -> some View {
        if usesIconOnlyOpenAndUpdate {
            ActionCapsuleIconButton(action: .update, onTap: action)
        } else {
            ActionCapsuleButton(action: .update, fullWidth: fullWidth, onTap: action)
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
