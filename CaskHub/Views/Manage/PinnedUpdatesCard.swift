//
//  PinnedUpdatesCard.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/11/2026.
//

import SwiftUI

struct PinnedUpdatesCard: View {
    let viewModel: CaskCatalogViewModel
    @State private var showsPicker = false
    @State private var note: BrewfileNote?

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
                        showsPicker = true
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
            if let note {
                Text(note.message)
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
        .sheet(isPresented: $showsPicker) {
            PinPickerSheet(viewModel: viewModel) { setPinned(true, cask: $0) }
        }
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
                    setPinned(false, cask: cask)
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

    private func isBusy(_ cask: Cask) -> Bool {
        localHomebrew.pinChangesInFlight.contains(cask.reference)
            || localHomebrew.operationStore.state(for: cask.reference) != nil
    }

    private func setPinned(_ pinned: Bool, cask: Cask) {
        Task {
            do {
                try await localHomebrew.setPinned(pinned, reference: cask.reference)
                note = nil
            } catch {
                note = BrewfileNote(message: error.localizedDescription, isFailure: true)
            }
        }
    }
}

struct PinPickerSheet: View {
    let viewModel: CaskCatalogViewModel
    let pin: (Cask) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

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
            .frame(maxHeight: 300)

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
        .frame(width: 400)
        .background(Color.chSurfaceHero)
    }

    private func pinnableRow(_ cask: Cask) -> some View {
        HStack(spacing: 10) {
            CaskIconView(cask: cask, size: 28, alignment: .center)
            Text(cask.displayName)
                .font(CHType.cardTitle)
                .foregroundStyle(Color.chTextTitle)
                .lineLimit(1)
            Spacer(minLength: 10)
            PillButton(
                title: String(localized: .shelfSetupPinPinButton),
                background: .chActionUpdateBg,
                border: .chActionUpdateBorder,
                foreground: .chActionUpdateFg
            ) {
                pin(cask)
            }
            .disabled(viewModel.localHomebrew.pinChangesInFlight.contains(cask.reference))
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }
}
