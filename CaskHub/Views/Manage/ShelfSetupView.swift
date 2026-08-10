//
//  ShelfSetupView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/08/2026.
//

import SwiftUI

struct ShelfSetupView: View {
    let viewModel: CaskCatalogViewModel
    @Environment(LocalHomebrewService.self) private var localHomebrew
    @State private var showsIgnorePicker = false

    var body: some View {
        ScrollView {
            ignoreCard
                .frame(maxWidth: 680, alignment: .leading)
                .frame(width: CHSize.contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .contentMargins(.bottom, 44, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showsIgnorePicker) {
            AdoptIgnorePickerSheet(viewModel: viewModel)
        }
    }

    // MARK: - Ignore List

    private var ignoreCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(String(localized: .shelfSetupIgnoreTitle))
                    .font(CHType.section)
                    .foregroundStyle(Color.chTextTitle)
                Spacer(minLength: 10)
                PillButton(
                    title: String(localized: .shelfSetupIgnoreAddButton),
                    background: .chSurfaceField,
                    border: .chHairlineStrong,
                    foreground: .chTextNav
                ) {
                    showsIgnorePicker = true
                }
            }
            Text(String(localized: .shelfSetupIgnoreDescription))
                .font(CHType.bodySm)
                .foregroundStyle(Color.chTextMuted)
                .padding(.top, 2)
                .padding(.bottom, 8)

            if viewModel.adoptIgnoredCasks.isEmpty {
                Text(String(localized: .shelfSetupIgnoreEmpty))
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
            } else {
                ForEach(viewModel.adoptIgnoredCasks) { cask in
                    ignoredRow(cask)
                }
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 20))
        .glassPanel()
    }

    private func ignoredRow(_ cask: Cask) -> some View {
        HStack(spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(cask.displayName)
                    .font(CHType.cardTitle)
                    .foregroundStyle(Color.chTextTitle)
                Text(cask.token)
                    .font(CHType.statusMono)
                    .foregroundStyle(Color.chTextFaint)
            }
            .lineLimit(1)
            Spacer(minLength: 10)
            if let when = localHomebrew.adoptIgnoredDates[cask.token] {
                Text(String(localized: .shelfSetupIgnoreIgnoredWhen(
                    when.formatted(.relative(presentation: .named))
                )))
                .font(CHType.statusMono)
                .foregroundStyle(Color.chTextFaint)
            }
            PillButton(
                title: String(localized: "Restore"),
                background: .chActionDoneBg,
                border: .chActionDoneBorder,
                foreground: .chActionDoneFg
            ) {
                localHomebrew.setAdoptIgnored(cask.token, false)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }
}

// MARK: - Page Chrome

struct UtilityTopBar: View {
    let title: String
    var summary: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(CHType.topBarTitle)
                .foregroundStyle(Color.chTextTitle)
            Spacer(minLength: 10)
            if let summary {
                Text(summary)
                    .font(CHType.countMeta)
                    .foregroundStyle(Color.chTextMuted)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
        .glassPanel(radius: 999, surface: .chSurfaceToolbar)
    }
}

struct MaintenancePlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            BarrelMark()
                .frame(width: 56, height: 56)
                .opacity(0.6)
            Text(String(localized: .maintenanceComingSoonTitle))
                .font(CHType.section)
                .foregroundStyle(Color.chTextTitle)
            Text(String(localized: .maintenanceComingSoonBody))
                .font(CHType.body)
                .foregroundStyle(Color.chTextBody)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Picker Sheet

struct AdoptIgnorePickerSheet: View {
    let viewModel: CaskCatalogViewModel
    @Environment(LocalHomebrewService.self) private var localHomebrew
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: .shelfSetupIgnorePickerTitle))
                .font(CHType.section)
                .foregroundStyle(Color.chTextTitle)
            Text(String(localized: .shelfSetupIgnorePickerSubtitle))
                .font(CHType.bodySm)
                .foregroundStyle(Color.chTextBody)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.adoptableCasks.isEmpty {
                        Text(String(localized: .shelfSetupIgnorePickerEmpty))
                            .font(CHType.bodySm)
                            .foregroundStyle(Color.chTextMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
                    } else {
                        ForEach(viewModel.adoptableCasks) { cask in
                            adoptableRow(cask)
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

    private func adoptableRow(_ cask: Cask) -> some View {
        HStack(spacing: 10) {
            CaskIconView(cask: cask, size: 28)
            Text(cask.displayName)
                .font(CHType.cardTitle)
                .foregroundStyle(Color.chTextTitle)
                .lineLimit(1)
            Spacer(minLength: 10)
            PillButton(
                title: String(localized: "Ignore"),
                background: .chActionUpdateBg,
                border: .chActionUpdateBorder,
                foreground: .chActionUpdateFg
            ) {
                localHomebrew.setAdoptIgnored(cask.token, true)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }
}

// MARK: - Shared Bits

private struct PillButton: View {
    let title: String
    let background: Color
    let border: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CHType.button)
                .foregroundStyle(foreground)
                .padding(.vertical, 4)
                .padding(.horizontal, 13)
                .background(Capsule().fill(background))
                .overlay(Capsule().strokeBorder(border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let categories = CategoryService()
    let recent = RecentlyAddedService()
    let homebrew = LocalHomebrewService()
    ShelfSetupView(viewModel: CaskCatalogViewModel(
        apiClient: BrewAPIClient(),
        categoryService: categories,
        recentlyAdded: recent,
        localHomebrew: homebrew
    ))
    .environment(homebrew)
    .environment(ImageCacheService())
    .frame(width: 1100, height: 600)
    .background(WindowBackdrop())
}
