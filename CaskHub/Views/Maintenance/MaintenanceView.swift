//
//  MaintenanceView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 19/08/2026.
//

import SwiftUI

struct MaintenanceView: View {
    let model: MaintenanceViewModel
    @State private var expandedChecks: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                healthCard
                HStack(alignment: .top, spacing: 16) {
                    homebrewWidget
                    syncWidget
                }
                MaintenanceDiskCard(model: model)
            }
            .frame(maxWidth: CHSize.contentWidth, alignment: .leading)
            .padding(.horizontal, CHSpace.s5)
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.25), value: model.checks)
            .animation(.easeOut(duration: 0.2), value: model.advisoriesExpanded)
        }
        .contentMargins(.bottom, 44, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .task { await model.refreshDisk() }
        .task { await model.refreshFreshness() }
    }

    // MARK: - Health

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: .maintenanceHealthCardTitle))
                        .font(CHType.section)
                        .foregroundStyle(Color.chTextTitle)
                    Text(model.healthSummary)
                        .font(CHType.bodySm)
                        .foregroundStyle(Color.chTextBody)
                }
                Spacer(minLength: 10)
                if !model.checks.isEmpty, !model.doctorRunning {
                    PillButton(
                        title: String(localized: model.advisoriesExpanded
                            ? .maintenanceHealthHide
                            : .maintenanceHealthReview),
                        background: .chSurfaceField,
                        border: .chHairlineStrong,
                        foreground: .chTextNav
                    ) {
                        model.advisoriesExpanded.toggle()
                    }
                }
                runCheckupButton
            }
            if model.advisoriesExpanded, !model.checks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.checks) { check in
                        checkRow(check)
                    }
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
        .glassPanel()
    }

    private var runCheckupButton: some View {
        Button {
            Task { await model.runCheckup() }
        } label: {
            HStack(spacing: 7) {
                if model.doctorRunning {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(String(localized: model.doctorRunning
                    ? .maintenanceHealthRunning
                    : .maintenanceHealthRun))
                    .font(CHType.button)
            }
            .foregroundStyle(Color.chActionInstallFg)
            .padding(.vertical, 5)
            .padding(.horizontal, 16)
            .background(Capsule().fill(Color.chActionInstallBg))
            .overlay(Capsule().strokeBorder(Color.chActionInstallBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.doctorRunning)
    }

    private func checkRow(_ check: HealthCheck) -> some View {
        HStack(alignment: .top, spacing: 12) {
            checkGlyph(check)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.label)
                    .font(CHType.cardTitle)
                    .foregroundStyle(Color.chTextTitle)
                if !check.detail.isEmpty {
                    checkDetail(check)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }

    private func checkGlyph(_ check: HealthCheck) -> some View {
        let passed = check.status == .pass
        return Text(passed ? "✓" : "!")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(passed ? Color.chActionDoneFg : Color.chActionUpdateFg)
            .frame(width: 22, height: 22)
            .background(Circle().fill(passed ? Color.chActionDoneBg : Color.chActionUpdateBg))
            .overlay(
                Circle().strokeBorder(
                    passed ? Color.chActionDoneBorder : Color.chActionUpdateBorder,
                    lineWidth: 1
                )
            )
    }

    @ViewBuilder
    private func checkDetail(_ check: HealthCheck) -> some View {
        let isExpanded = expandedChecks.contains(check.id)
        Text(check.detail)
            .font(CHType.bodySm)
            .foregroundStyle(Color.chTextBody)
            .lineLimit(isExpanded ? nil : Self.collapsedDetailLines)
            .textSelection(.enabled)
        if check.detail.split(separator: "\n").count > Self.collapsedDetailLines {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if isExpanded {
                        expandedChecks.remove(check.id)
                    } else {
                        expandedChecks.insert(check.id)
                    }
                }
            } label: {
                Text(String(localized: isExpanded
                    ? .maintenanceHealthShowLess
                    : .maintenanceHealthShowMore))
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextBrand)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    private static let collapsedDetailLines = 4

}

// MARK: - Widgets

extension MaintenanceView {
    private var homebrewWidget: some View {
        maintenanceWidget(
            title: String(localized: .maintenanceWidgetHomebrewTitle),
            detail: model.brewVersion.map {
                String(localized: .maintenanceWidgetHomebrewDetail($0, model.brewPrefix ?? "?"))
            } ?? String(localized: .maintenanceWidgetHomebrewMissing),
            meta: homebrewMeta.text,
            metaColor: homebrewMeta.color
        ) {
            switch model.homebrewState {
            case .idle where model.brewFreshness == .current:
                StatusPill(
                    title: String(localized: .maintenanceUpToDate),
                    background: .chActionDoneBg,
                    border: .chActionDoneBorder,
                    foreground: .chActionDoneFg
                )
            case .idle:
                PillButton(
                    title: String(localized: .maintenanceWidgetHomebrewButton),
                    background: .chActionUpdateBg,
                    border: .chActionUpdateBorder,
                    foreground: .chActionUpdateFg
                ) {
                    Task { await model.updateHomebrew() }
                }
                .disabled(model.brewVersion == nil || model.hasActiveOperations)
            case .running:
                WorkingPill(title: String(localized: .maintenanceWorking))
            case .done:
                StatusPill(
                    title: String(localized: .maintenanceWidgetHomebrewDone),
                    background: .chActionDoneBg,
                    border: .chActionDoneBorder,
                    foreground: .chActionDoneFg
                )
            }
        }
    }

    private var homebrewMeta: (text: String, color: Color) {
        if model.homebrewFailed {
            return (String(localized: .maintenanceWidgetHomebrewFailed), .chActionUpdateFg)
        }
        switch model.brewFreshness {
        case .current:
            return (String(localized: .maintenanceWidgetHomebrewLatest), .chActionDoneFg)
        case let .updateAvailable(version):
            return (
                String(localized: .maintenanceWidgetHomebrewUpdateAvailable(version)),
                .chActionUpdateFg
            )
        case .unknown:
            return (String(localized: .maintenanceWidgetHomebrewHint), .chTextFaint)
        }
    }

    private var syncWidget: some View {
        maintenanceWidget(
            title: String(localized: .maintenanceWidgetSyncTitle),
            detail: model.lastSyncedAt.map {
                String(localized: .maintenanceWidgetSyncDetail(
                    $0.formatted(.relative(presentation: .named))
                ))
            } ?? String(localized: .maintenanceWidgetSyncNever),
            meta: syncMeta.text,
            metaColor: syncMeta.color
        ) {
            switch model.syncState {
            case .idle where model.collectionFreshness == .current:
                StatusPill(
                    title: String(localized: .maintenanceUpToDate),
                    background: .chActionDoneBg,
                    border: .chActionDoneBorder,
                    foreground: .chActionDoneFg
                )
            case .idle:
                PillButton(
                    title: String(localized: .maintenanceWidgetSyncButton),
                    background: .chActionInstallBg,
                    border: .chActionInstallBorder,
                    foreground: .chActionInstallFg
                ) {
                    Task { await model.syncCollection() }
                }
            case .running:
                WorkingPill(title: String(localized: .maintenanceWidgetSyncRunning))
            case .done:
                StatusPill(
                    title: String(localized: .maintenanceWidgetSyncDone),
                    background: .chActionDoneBg,
                    border: .chActionDoneBorder,
                    foreground: .chActionDoneFg
                )
            }
        }
    }

    private var syncMeta: (text: String, color: Color) {
        switch model.collectionFreshness {
        case .current:
            return (
                String(localized: .maintenanceWidgetSyncLatest(model.caskFlowReleaseTag ?? "")),
                .chActionDoneFg
            )
        case let .updateAvailable(version):
            return (
                String(localized: .maintenanceWidgetSyncUpdateAvailable(version)),
                .chActionUpdateFg
            )
        case .unknown:
            return (
                String(localized: .maintenanceWidgetSyncMeta(model.installedCount)),
                model.syncState == .done ? .chActionDoneFg : .chTextFaint
            )
        }
    }

    private func maintenanceWidget(
        title: String,
        detail: String,
        meta: String,
        metaColor: Color,
        @ViewBuilder control: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CHType.section)
                .foregroundStyle(Color.chTextTitle)
            Text(detail)
                .font(CHType.bodySm)
                .foregroundStyle(Color.chTextBody)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Text(meta)
                    .font(CHType.statusMono)
                    .foregroundStyle(metaColor)
                    .lineLimit(1)
                Spacer(minLength: 8)
                control()
            }
            .padding(.top, 2)
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }
}

// MARK: - Shared Pills

struct WorkingPill: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text(title)
                .font(CHType.button)
        }
        .foregroundStyle(Color.chTextMuted)
        .padding(.vertical, 4)
        .padding(.horizontal, 13)
        .background(Capsule().fill(Color.chSurfaceField))
        .overlay(Capsule().strokeBorder(Color.chHairlineStrong, lineWidth: 1))
    }
}

struct StatusPill: View {
    let title: String
    let background: Color
    let border: Color
    let foreground: Color

    var body: some View {
        Text(title)
            .font(CHType.button)
            .foregroundStyle(foreground)
            .padding(.vertical, 4)
            .padding(.horizontal, 13)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
    }
}

#Preview {
    let categories = CategoryService()
    let recent = RecentlyAddedService()
    let homebrew = LocalHomebrewService()
    let catalog = CaskCatalogViewModel(
        apiClient: BrewAPIClient(),
        categoryService: categories,
        recentlyAdded: recent,
        localHomebrew: homebrew
    )
    MaintenanceView(model: MaintenanceViewModel(
        localHomebrew: homebrew,
        catalog: catalog,
        clearImageCache: {}
    ))
    .frame(width: 1100, height: 700)
    .background(WindowBackdrop())
}
