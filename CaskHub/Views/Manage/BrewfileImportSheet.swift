//
//  BrewfileImportSheet.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/08/2026.
//

import SwiftUI

// MARK: - Brewfile Import

nonisolated struct BrewfileNote {
    let message: String
    let isFailure: Bool
}

nonisolated struct BrewfileImportPlan: Identifiable {
    nonisolated struct Entry: Identifiable {
        let token: String
        let cask: Cask?

        var id: String { token }
        var displayName: String { cask?.displayName ?? token }
    }

    let id = UUID()
    let fileName: String
    let skippedEntries: [Entry]
    let newEntries: [Entry]

    var listedCount: Int { skippedEntries.count + newEntries.count }
}

nonisolated enum BrewfileImportPhase: Equatable {
    case preview
    case running(index: Int)
    case done(failedCount: Int)
}

struct BrewfileImportSheet: View {
    let plan: BrewfileImportPlan
    @Environment(LocalHomebrewService.self) private var localHomebrew
    @Environment(\.dismiss) private var dismiss
    @State private var phase: BrewfileImportPhase
    @State private var selectedTokens: Set<String>

    init(plan: BrewfileImportPlan, phase: BrewfileImportPhase = .preview) {
        self.plan = plan
        _phase = State(initialValue: phase)
        _selectedTokens = State(initialValue: Set(plan.newEntries.map(\.token)))
    }

    private var selectedEntries: [BrewfileImportPlan.Entry] {
        plan.newEntries.filter { selectedTokens.contains($0.token) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: .shelfSetupBrewfileSheetTitle))
                .font(CHType.section)
                .foregroundStyle(Color.chTextTitle)
            Text(String(localized: .shelfSetupBrewfileSheetSubtitle(
                plan.fileName, plan.listedCount
            )))
            .font(CHType.statusMono)
            .foregroundStyle(Color.chTextMuted)

            switch phase {
            case .preview:
                preview
            case let .running(index):
                progress(index: index)
            case let .done(failedCount):
                summary(failedCount: failedCount)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(Color.chSurfaceHero)
        .interactiveDismissDisabled(isRunning)
    }

    private var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    @ViewBuilder private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            if plan.newEntries.isEmpty {
                Text(String(localized: .shelfSetupBrewfileSheetNothingNew))
                    .font(CHType.bodySm)
                    .foregroundStyle(Color.chTextMuted)
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
            } else {
                selectAllRow
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(plan.newEntries) { entry in
                        BrewfileEntryRow(entry: entry, isSelected: selectionBinding(entry))
                    }
                    if !plan.skippedEntries.isEmpty {
                        skippedHeader
                        ForEach(plan.skippedEntries) { entry in
                            BrewfileEntryRow(entry: entry)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        HStack(spacing: 8) {
            Spacer()
            PillButton(
                title: String(localized: plan.newEntries.isEmpty ? "Done" : "Cancel"),
                background: .chSurfaceField,
                border: .chHairlineStrong,
                foreground: .chTextNav
            ) {
                dismiss()
            }
            if !plan.newEntries.isEmpty {
                PillButton(
                    title: String(localized: .shelfSetupBrewfileSheetInstallButton(
                        selectedEntries.count
                    )),
                    background: .chActionInstallBg,
                    border: .chActionInstallBorder,
                    foreground: .chActionInstallFg,
                    action: runImport
                )
                .disabled(selectedEntries.isEmpty)
                .opacity(selectedEntries.isEmpty ? 0.5 : 1)
            }
        }
        .padding(.top, 6)
    }

    private func selectionBinding(_ entry: BrewfileImportPlan.Entry) -> Binding<Bool> {
        Binding(
            get: { selectedTokens.contains(entry.token) },
            set: { selected in
                if selected {
                    selectedTokens.insert(entry.token)
                } else {
                    selectedTokens.remove(entry.token)
                }
            }
        )
    }

    private var selectAllRow: some View {
        let allSelected = selectedTokens.count == plan.newEntries.count
        return Toggle(isOn: Binding(
            get: { allSelected },
            set: { selectAll in
                selectedTokens = selectAll ? Set(plan.newEntries.map(\.token)) : []
            }
        )) {
            Text(String(localized: allSelected
                ? .shelfSetupBrewfileSheetDeselectAll
                : .shelfSetupBrewfileSheetSelectAll))
                .font(CHType.cardTitle)
                .foregroundStyle(Color.chTextTitle)
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }

    private var skippedHeader: some View {
        HStack(spacing: 8) {
            BrewfileDoneMark(size: 16)
            Text(String(localized: .shelfSetupBrewfileSheetSkipped(
                plan.skippedEntries.count
            )))
            .font(CHType.bodySm)
            .foregroundStyle(Color.chTextBody)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }

    private func progress(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                Capsule()
                    .fill(Color.chTerracotta)
                    .frame(
                        width: geo.size.width * CGFloat(index) / CGFloat(selectedEntries.count)
                    )
            }
            .frame(height: 8)
            .background(Capsule().fill(Color.chSurfaceField))
            .overlay(Capsule().strokeBorder(Color.chHairline, lineWidth: 1))
            .animation(.linear(duration: 0.15), value: index)
            Text(String(localized: .shelfSetupBrewfileSheetPouring(
                selectedEntries[index].displayName,
                index + 1,
                selectedEntries.count
            )))
            .font(CHType.statusMono)
            .foregroundStyle(Color.chTextMuted)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private func summary(failedCount: Int) -> some View {
        HStack(spacing: 10) {
            BrewfileDoneMark(size: 20)
            Text(
                failedCount == 0
                    ? String(localized: .shelfSetupBrewfileSheetDone(selectedEntries.count))
                    : String(localized: .shelfSetupBrewfileSheetDoneWithFailures(
                        selectedEntries.count - failedCount,
                        selectedEntries.count,
                        failedCount
                    ))
            )
            .font(CHType.bodySm)
            .foregroundStyle(Color.chTextBody)
        }
        .padding(.vertical, 6)
        HStack {
            Spacer()
            PillButton(
                title: String(localized: "Done"),
                background: .chActionDoneBg,
                border: .chActionDoneBorder,
                foreground: .chActionDoneFg
            ) {
                dismiss()
            }
        }
    }

    private func runImport() {
        guard case .preview = phase, !selectedEntries.isEmpty else { return }
        phase = .running(index: 0)
        Task {
            var failedCount = 0
            for (index, entry) in selectedEntries.enumerated() {
                phase = .running(index: index)
                do {
                    try await localHomebrew.install(token: entry.token)
                } catch {
                    failedCount += 1
                }
            }
            phase = .done(failedCount: failedCount)
        }
    }
}

// MARK: - Rows

/// Checkbox row when `isSelected` is bound; dimmed installed row when nil.
private struct BrewfileEntryRow: View {
    let entry: BrewfileImportPlan.Entry
    var isSelected: Binding<Bool>?

    var body: some View {
        HStack(spacing: 10) {
            if let isSelected {
                Toggle(isOn: isSelected) {
                    Text(entry.displayName)
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 16)
            } else {
                BrewfileDoneMark(size: 14)
                    .frame(width: 16)
            }
            BrewfileEntryIcon(entry: entry)
            Text(entry.displayName)
                .font(CHType.cardTitle)
                .foregroundStyle(Color.chTextTitle)
                .lineLimit(1)
            Spacer(minLength: 10)
            if let cask = entry.cask {
                Text(verbatim: "v\(cask.displayVersion)")
                    .font(CHType.statusMono)
                    .foregroundStyle(Color.chTextFaint)
            }
        }
        .padding(.vertical, 7)
        .opacity(isSelected == nil ? 0.55 : 1)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }
}

private struct BrewfileEntryIcon: View {
    let entry: BrewfileImportPlan.Entry

    var body: some View {
        if let cask = entry.cask {
            CaskIconView(cask: cask, size: 26)
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.chSurfaceField)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.chHairline, lineWidth: 1)
                )
                .overlay(
                    Text(entry.token.prefix(1).uppercased())
                        .font(CHType.cardTitle)
                        .foregroundStyle(Color.chTextFaint)
                )
                .frame(width: 26, height: 26)
        }
    }
}

private struct BrewfileDoneMark: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color.chActionDoneFg)
    }
}
