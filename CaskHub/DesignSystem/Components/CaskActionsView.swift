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
        let presentation = localHomebrew.actionPresentation(
            for: cask,
            localState: localState
        )
        let state = presentation.localState
        if let inFlight = presentation.activeAction {
            inFlightCapsule(for: inFlight, presentation: presentation)
        } else if state.isHomebrewInstalled {
            installedActions(state)
        } else if state.isAdoptable {
            HStack(spacing: 8) {
                if isAdoptPage {
                    ActionCapsuleButton(action: .adopt, fullWidth: fullWidth) {
                        if state.isExternalPackage {
                            localHomebrew.send(.requestPackageAdoption(token: cask.token))
                        } else {
                            localHomebrew.send(.adopt(cask))
                        }
                    }
                } else {
                    openButton(fullWidth: fullWidth) {
                        localHomebrew.send(.openExternal(cask))
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
                    localHomebrew.send(.openExternal(cask))
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
                localHomebrew.send(.install(token: cask.token))
            }
        }
    }

    @ViewBuilder
    private func installedActions(_ state: CaskLocalState) -> some View {
        if state.isZombie {
            ActionCapsuleButton(action: .cleanup, fullWidth: fullWidth) {
                localHomebrew.send(.repair(token: cask.token))
            }
            .help(String(
                localized: "action.cleanup.zombieHelp",
                defaultValue: """
                \(cask.displayName) was removed outside Homebrew, but Homebrew still \
                has records for it. Clean Up removes the leftover data.
                """,
                comment: "Tooltip on the Clean Up button for a zombie cask"
            ))
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
                    localHomebrew.send(.open(cask))
                }
            }
            if state.hasAvailableUpdate {
                updateButton(fullWidth: fullWidth) {
                    localHomebrew.send(.update(token: cask.token))
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

    private func inFlightCapsule(
        for action: CaskAction,
        presentation: CaskActionPresentation
    ) -> some View {
        let token = cask.token

        return CaskOperationCapsule(
            action: action,
            progress: presentation.progress,
            isCanceling: presentation.isCanceling,
            canCancel: presentation.canCancel,
            fullWidth: fullWidth,
            onCancel: { localHomebrew.send(.cancel(token: token)) }
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
