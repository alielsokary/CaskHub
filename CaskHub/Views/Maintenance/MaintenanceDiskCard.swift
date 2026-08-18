//
//  MaintenanceDiskCard.swift
//  CaskHub
//
//  Created by Ali Elsokary on 19/08/2026.
//

import AppKit
import SwiftUI

struct MaintenanceDiskCard: View {
    typealias CategoryID = MaintenanceViewModel.DiskCategoryID

    let model: MaintenanceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            usageBar
                .padding(.top, 12)
                .padding(.bottom, 14)
            ForEach(CategoryID.allCases) { id in
                diskRow(id)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 20))
        .glassPanel()
        .animation(.easeOut(duration: 0.2), value: model.expandedRows)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(localized: .maintenanceDiskTitle))
                    .font(CHType.section)
                    .foregroundStyle(Color.chTextTitle)
                Spacer(minLength: 10)
                if let total = totalBytes {
                    Text(String(localized: .maintenanceDiskTotal(MaintenanceFormat.bytes(total))))
                        .font(CHType.statusMono)
                        .foregroundStyle(Color.chTextMuted)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.reclaimableBytes.map(MaintenanceFormat.bytes) ?? "…")
                    .font(CHType.heroTitle)
                    .foregroundStyle(Color.chTextTitle)
                Text(String(localized: .maintenanceDiskReclaimable))
                    .font(CHType.body)
                    .foregroundStyle(Color.chTextMuted)
            }
        }
    }

    private var totalBytes: Int64? {
        guard let reclaimable = model.reclaimableBytes else { return nil }
        return reclaimable + (model.diskBytes[.apps] ?? 0)
    }

    // MARK: - Bar

    private var usageBar: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(CategoryID.allCases) { id in
                    tint(for: id)
                        .opacity(dotOpacity(for: id))
                        .frame(width: geo.size.width * fraction(of: id))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 16)
        .background(Capsule().fill(Color.chSurfaceField))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.chHairline, lineWidth: 1))
    }

    private func fraction(of id: CategoryID) -> CGFloat {
        guard let total = totalBytes, total > 0 else { return 0 }
        return CGFloat(model.diskBytes[id] ?? 0) / CGFloat(total)
    }

    // MARK: - Rows

    private func diskRow(_ id: CategoryID) -> some View {
        let state = model.rowStates[id, default: .idle]
        let isExpanded = model.expandedRows.contains(id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint(for: id))
                    .opacity(state == .done ? 0.22 : dotOpacity(for: id))
                    .frame(width: 9, height: 9)
                Button {
                    if isExpanded {
                        model.expandedRows.remove(id)
                    } else {
                        model.expandedRows.insert(id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(label(for: id))
                            .font(CHType.cardTitle)
                            .foregroundStyle(Color.chTextTitle)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Color.chTextFaint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 185, alignment: .leading)
                Text(description(for: id, state: state))
                    .font(CHType.bodySm)
                    .foregroundStyle(descriptionColor(for: id, state: state))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(sizeText(for: id))
                    .font(CHType.statusMono)
                    .foregroundStyle(Color.chTextMuted)
                actionArea(for: id, state: state)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 33)
            if isExpanded {
                directoryList(for: id)
            }
        }
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }

    @ViewBuilder
    private func actionArea(for id: CategoryID, state: MaintenanceViewModel.TaskState) -> some View {
        switch state {
        case .running:
            WorkingPill(title: String(localized: .maintenanceWorking))
        case .idle where buttonTitle(for: id) != nil && (model.diskBytes[id] ?? 0) > 0:
            PillButton(
                title: buttonTitle(for: id) ?? "",
                background: .chActionUpdateBg,
                border: .chActionUpdateBorder,
                foreground: .chActionUpdateFg
            ) {
                Task { await model.clean(id) }
            }
            .frame(width: 74)
        default:
            Color.clear.frame(width: 74, height: 1)
        }
    }

    private func directoryList(for id: CategoryID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.directories(for: id), id: \.path) { url in
                HStack(spacing: 10) {
                    Text((url.path as NSString).abbreviatingWithTildeInPath)
                        .font(CHType.statusMono)
                        .foregroundStyle(Color.chTextMuted)
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.chTextMuted)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: .maintenanceDiskOpenFinder))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.leading, 21)
        .padding(.bottom, 8)
    }

    // MARK: - Row Metadata

    private func tint(for id: CategoryID) -> Color {
        switch id {
        case .apps: return .chSage
        case .cache: return .chTerracotta
        case .oldVersions: return .chAmber
        case .orphans: return .chPlum
        case .imageCache: return .chAmber
        }
    }

    private func dotOpacity(for id: CategoryID) -> Double {
        switch id {
        case .apps: return 0.55
        case .cache: return 0.8
        case .oldVersions: return 0.85
        case .orphans: return 0.75
        case .imageCache: return 0.5
        }
    }

    private func label(for id: CategoryID) -> String {
        switch id {
        case .apps: return String(localized: .maintenanceDiskAppsLabel)
        case .cache: return String(localized: .maintenanceDiskCacheLabel)
        case .oldVersions: return String(localized: .maintenanceDiskOldLabel)
        case .orphans: return String(localized: .maintenanceDiskOrphansLabel)
        case .imageCache: return String(localized: .maintenanceDiskImageCacheLabel)
        }
    }

    private func description(for id: CategoryID, state: MaintenanceViewModel.TaskState) -> String {
        if model.failedRows.contains(id) {
            return String(localized: .maintenanceDiskFailed)
        }
        if state == .done, let done = doneDescription(for: id) {
            return done
        }
        return idleDescription(for: id)
    }

    private func doneDescription(for id: CategoryID) -> String? {
        switch id {
        case .apps: return nil
        case .cache: return String(localized: .maintenanceDiskCacheDone)
        case .oldVersions: return String(localized: .maintenanceDiskOldDone)
        case .orphans: return String(localized: .maintenanceDiskOrphansDone)
        case .imageCache: return String(localized: .maintenanceDiskImageCacheDone)
        }
    }

    private func idleDescription(for id: CategoryID) -> String {
        switch id {
        case .apps:
            return String(localized: .maintenanceDiskAppsDesc(model.installedCount))
        case .cache:
            return String(localized: .maintenanceDiskCacheDesc)
        case .oldVersions:
            return String(localized: .maintenanceDiskOldDesc)
        case .orphans:
            return model.orphanFormulae.isEmpty
                ? String(localized: .maintenanceDiskOrphansEmpty)
                : model.orphanFormulae.joined(separator: ", ")
        case .imageCache:
            return String(localized: .maintenanceDiskImageCacheDesc)
        }
    }

    private func descriptionColor(for id: CategoryID, state: MaintenanceViewModel.TaskState) -> Color {
        if model.failedRows.contains(id) { return .chActionUpdateFg }
        return state == .done ? .chActionDoneFg : .chTextMuted
    }

    private func sizeText(for id: CategoryID) -> String {
        guard let bytes = model.diskBytes[id] else { return "…" }
        return MaintenanceFormat.bytes(bytes)
    }

    private func buttonTitle(for id: CategoryID) -> String? {
        switch id {
        case .apps: return nil
        case .cache, .oldVersions: return String(localized: .maintenanceDiskClean)
        case .orphans: return String(localized: .maintenanceDiskOrphansButton)
        case .imageCache: return String(localized: .maintenanceDiskImageCacheButton)
        }
    }
}
