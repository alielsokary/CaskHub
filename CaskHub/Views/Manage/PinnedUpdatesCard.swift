//
//  PinnedUpdatesCard.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/11/2026.
//

import SwiftUI

struct PinnedUpdatesCard: View {
    static let selfUpdatingSymbol = LibraryItem.updates.icon

    let viewModel: CaskCatalogViewModel
    @Binding var picker: ShelfSetupPicker?

    private var localHomebrew: LocalHomebrewService {
        viewModel.localHomebrew
    }

    var canPin: Bool {
        localHomebrew.supportsCaskPinning
    }

    func pinnedLabel(for cask: Cask) -> String? {
        localHomebrew.pinnedVersion(for: cask.reference).map {
            String(localized: .shelfSetupPinPinnedAt(Cask.displayVersion(of: $0)))
        }
    }

    func selfUpdatingHelp(for cask: Cask) -> String? {
        cask.autoUpdates == true ? String(localized: .shelfSetupPinSelfUpdatingHint(cask.token)) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(String(localized: .shelfSetupPinTitle))
                    .font(CHType.section)
                    .foregroundStyle(Color.chTextTitle)
                Spacer(minLength: 10)
                if canPin {
                    PillButton(
                        title: String(localized: .shelfSetupPinAddButton),
                        background: .chSurfaceField,
                        border: .chHairlineStrong,
                        foreground: .chTextNav
                    ) {
                        picker = .pin
                    }
                }
            }
            Text(String(localized: .shelfSetupPinDescription))
                .font(CHType.bodySm)
                .foregroundStyle(Color.chTextMuted)
                .padding(.top, 2)
            if !canPin {
                Text(String(localized: .shelfSetupPinNeedsHomebrew))
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextMuted)
                    .padding(.top, 2)
            }
            if let failure = localHomebrew.pinFailureMessage {
                Text(failure)
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chActionUpdateFg)
                    .padding(.top, 2)
            }
            Spacer().frame(height: 8)

            let pinnedCasks = viewModel.pinnedCasks
            if pinnedCasks.isEmpty {
                Text(String(localized: .shelfSetupPinEmpty))
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
            } else {
                ForEach(pinnedCasks) { cask in
                    pinnedRow(cask)
                        .transition(.opacity)
                }
            }
        }
        .animation(.snappy, value: viewModel.pinnedCasks.map(\.reference))
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 20))
        .glassPanel()
    }

    private func pinnedRow(_ cask: Cask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(cask.displayName)
                        .font(CHType.cardTitle)
                        .foregroundStyle(Color.chTextTitle)
                    Text(verbatim: cask.token)
                        .font(CHType.statusMono)
                        .foregroundStyle(Color.chTextFaint)
                    if let help = selfUpdatingHelp(for: cask) {
                        Image(systemName: Self.selfUpdatingSymbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.chTextFaint)
                            .hoverHint(help)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 10)
                if let label = pinnedLabel(for: cask) {
                    Text(label)
                        .font(CHType.statusMono)
                        .foregroundStyle(Color.chTextFaint)
                }
                PillButton(
                    title: String(localized: .shelfSetupPinUnpinButton),
                    background: .chActionDoneBg,
                    border: .chActionDoneBorder,
                    foreground: .chActionDoneFg,
                    isLoading: localHomebrew.pinChangesInFlight.contains(cask.reference)
                ) {
                    Task { try? await localHomebrew.setPinned(false, reference: cask.reference) }
                }
                .disabled(localHomebrew.isPinBlocked(cask.reference))
                .opacity(localHomebrew.isPinBlocked(cask.reference) ? 0.5 : 1)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }
}

struct PinPickerSheet: View {
    let viewModel: CaskCatalogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// Homebrew's version, the one a pin keeps, so it matches the card's "pinned at".
    func installedVersion(for cask: Cask) -> String? {
        viewModel.localHomebrew.installationSnapshot.installation(for: cask.reference)
            .map { Cask.displayVersion(of: $0.installedVersion) }
    }

    static func emptyMessage(query: String) -> String {
        query.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(localized: .shelfSetupPinPickerEmpty)
            : String(localized: .shelfSetupPinPickerNoMatches)
    }

    var body: some View {
        let casks = viewModel.pinnableCasks(matching: query)
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: .shelfSetupPinPickerTitle))
                .font(CHType.section)
                .foregroundStyle(Color.chTextTitle)
            Text(String(localized: .shelfSetupPinPickerSubtitle))
                .font(CHType.bodySm)
                .foregroundStyle(Color.chTextBody)
            if let failure = viewModel.localHomebrew.pinFailureMessage {
                Text(failure)
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chActionUpdateFg)
            }
            NativeSearchField(text: $query, prompt: String(localized: .shelfSetupPinFilterPrompt))

            ScrollView {
                LazyVStack(spacing: 0) {
                    if casks.isEmpty {
                        Text(Self.emptyMessage(query: query))
                            .font(CHType.bodySm)
                            .foregroundStyle(Color.chTextMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
                    } else {
                        ForEach(casks) { cask in
                            pinnableRow(cask)
                                .transition(.opacity)
                        }
                    }
                }
                .animation(.snappy, value: casks.map(\.reference))
            }
            .frame(height: 300)

            HStack {
                Spacer()
                PillButton(
                    title: String(localized: "Done"),
                    background: .chSurfaceField,
                    border: .chHairlineStrong,
                    foreground: .chTextNav
                ) {
                    dismiss()
                }
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(width: 460)
        .background(Color.chSurfaceHero)
    }

    private func pinnableRow(_ cask: Cask) -> some View {
        HStack(spacing: 10) {
            CaskIconView(cask: cask, size: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(cask.displayName)
                    .font(CHType.cardTitle)
                    .foregroundStyle(Color.chTextTitle)
                if let version = installedVersion(for: cask) {
                    Text(verbatim: version)
                        .font(CHType.statusMono)
                        .foregroundStyle(Color.chTextFaint)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 10)
            PillButton(
                title: String(localized: .shelfSetupPinPinButton),
                background: .chActionUpdateBg,
                border: .chActionUpdateBorder,
                foreground: .chActionUpdateFg,
                isLoading: viewModel.localHomebrew.pinChangesInFlight.contains(cask.reference)
            ) {
                Task { try? await viewModel.localHomebrew.setPinned(true, reference: cask.reference) }
            }
            .disabled(viewModel.localHomebrew.isPinBlocked(cask.reference))
            .opacity(viewModel.localHomebrew.isPinBlocked(cask.reference) ? 0.5 : 1)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }
}
