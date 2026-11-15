//
//  PinnedUpdatesCard.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/11/2026.
//

import SwiftUI

struct PinnedUpdatesCard: View {
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
            String(localized: .shelfSetupPinPinnedAt($0))
        }
    }

    func showsSelfUpdatingHint(_ cask: Cask) -> Bool {
        cask.autoUpdates == true
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

            if viewModel.pinnedCasks.isEmpty {
                Text(String(localized: .shelfSetupPinEmpty))
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
            } else {
                ForEach(viewModel.pinnedCasks) { cask in
                    pinnedRow(cask)
                }
            }
        }
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
                    foreground: .chActionDoneFg
                ) {
                    Task { try? await localHomebrew.setPinned(false, reference: cask.reference) }
                }
                .disabled(isBusy(cask))
                .opacity(isBusy(cask) ? 0.5 : 1)
            }
            if showsSelfUpdatingHint(cask) {
                Text(String(localized: .shelfSetupPinSelfUpdatingHint))
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextMuted)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }

    func isBusy(_ cask: Cask) -> Bool {
        !localHomebrew.canChangePin(for: cask.reference)
    }
}

struct PinPickerSheet: View {
    let viewModel: CaskCatalogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// Same precedence as the detail page's Installed row.
    func installedVersion(for cask: Cask) -> String? {
        viewModel.localState(for: cask).homebrewAppVersion
            ?? viewModel.localHomebrew.installationSnapshot.installation(for: cask.reference)?.installedVersion
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
                        }
                    }
                }
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
                foreground: .chActionUpdateFg
            ) {
                Task { try? await viewModel.localHomebrew.setPinned(true, reference: cask.reference) }
            }
            .disabled(!viewModel.localHomebrew.canChangePin(for: cask.reference))
            .opacity(viewModel.localHomebrew.canChangePin(for: cask.reference) ? 1 : 0.5)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }
}
