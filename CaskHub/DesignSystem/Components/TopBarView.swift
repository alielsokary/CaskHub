//
//  TopBarView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/07/2026.
//

import SwiftUI

struct TopBarTitle: ToolbarContent {
    let title: String
    var summary: String?

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            item.sharedBackgroundVisibility(.hidden)
        } else {
            item
        }
    }

    private var item: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(CHType.topBarTitle)
                    .foregroundStyle(Color.chTextTitle)
                if let summary {
                    Text(summary)
                        .font(CHType.countMeta)
                        .foregroundStyle(CHType.isNative ? Color.chTextBody : Color.chTextMuted)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, 4)
            // Toolbar items keep their first measured width; a new identity re-measures.
            .id(title)
        }
    }
}

struct CatalogToolbar: ToolbarContent {
    @Binding var sortOption: SortOption
    var sortOptions: [SortOption] = SortOption.standard
    @Binding var viewMode: ViewMode
    var analyticsPeriod: AnalyticsPeriod?
    var onSelectPeriod: ((AnalyticsPeriod) -> Void)?
    var recentWindow: RecentlyAddedWindow?
    var onSelectWindow: ((RecentlyAddedWindow) -> Void)?
    var onUpdateAll: (() -> Void)?
    var updateAllCount = 0
    var isUpdatingAll: Bool
    var isUpdatingHomebrew: Bool
    let onRefreshUpdates: (() -> Void)?
    let isRefreshingUpdates: Bool
    var greedyUpdates: Bool?
    var onToggleGreedy: ((Bool) -> Void)?
    var showsSort = true
    var onRefreshTaps: (() -> Void)?
    var isRefreshingTaps = false
    var onAddTap: (() -> Void)?

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        }
        updatesControls
        tapControls
        if showsSort {
            ToolbarItem(placement: .automatic) {
                OptionMenu(current: sortOption, options: sortOptions, label: \.title, systemImage: "arrow.up.arrow.down") {
                    if $0 != sortOption { Analytics.sortChanged($0) }
                    sortOption = $0
                }
            }
        }
        if showsSort, analyticsPeriod != nil || recentWindow != nil, #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
        if let analyticsPeriod {
            ToolbarItem(placement: .automatic) {
                OptionMenu(current: analyticsPeriod, options: AnalyticsPeriod.allCases, label: \.label, systemImage: "clock") {
                    onSelectPeriod?($0)
                }
            }
        }
        if let recentWindow {
            ToolbarItem(placement: .automatic) {
                OptionMenu(current: recentWindow, options: RecentlyAddedWindow.allCases, label: \.label, systemImage: "clock") {
                    onSelectWindow?($0)
                }
            }
        }
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
        ToolbarItem(placement: .automatic) {
            Picker("View Mode", selection: $viewMode) {
                Label("Grid", systemImage: "square.grid.2x2").tag(ViewMode.grid)
                Label("List", systemImage: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
        }
    }

    // ToolbarContentBuilder takes at most ten statements on Xcode 26.
    @ToolbarContentBuilder private var updatesControls: some ToolbarContent {
        if let greedyUpdates {
            ToolbarItem(placement: .automatic) {
                GreedyButton(isOn: greedyUpdates) { onToggleGreedy?($0) }
            }
        }
        if greedyUpdates != nil, onUpdateAll != nil, #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
        if let onUpdateAll {
            ToolbarItem(placement: .automatic) {
                UpdateAllButton(
                    count: updateAllCount,
                    isUpdatingAll: isUpdatingAll,
                    isUpdatingHomebrew: isUpdatingHomebrew,
                    onUpdateAll: onUpdateAll
                )
            }
        }
        if onRefreshUpdates != nil, #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
        if let onRefreshUpdates {
            ToolbarItem(placement: .automatic) {
                RefreshUpdatesButton(isRefreshing: isRefreshingUpdates, action: onRefreshUpdates)
            }
        }
        if onRefreshUpdates != nil, showsSort, #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
    }

    @ToolbarContentBuilder private var tapControls: some ToolbarContent {
        if let onRefreshTaps {
            ToolbarItem(placement: .automatic) {
                Button(action: onRefreshTaps) {
                    if isRefreshingTaps {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshingTaps)
                .help(Text("Refresh Taps"))
                .accessibilityLabel(Text("Refresh Taps"))
            }
        }
        if onRefreshTaps != nil, onAddTap != nil, #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
        if let onAddTap {
            ToolbarItem(placement: .automatic) {
                Button(action: onAddTap) {
                    Image(systemName: "plus")
                }
                .help(Text("Add Tap"))
                .accessibilityLabel(Text("Add Tap"))
            }
        }
        if onAddTap != nil, #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
    }
}

private struct OptionMenu<Option: Identifiable & Equatable>: View {
    let current: Option
    let options: [Option]
    let label: KeyPath<Option, String>
    let systemImage: String
    let onSelect: (Option) -> Void

    var body: some View {
        Menu {
            ForEach(options) { option in
                Toggle(option[keyPath: label], isOn: Binding(get: { option == current }, set: { _ in onSelect(option) }))
            }
        } label: {
            HStack(spacing: 6) {
                Label(current[keyPath: label], systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, CHSpace.toolbarLabelInset)
        }
        .menuIndicator(.hidden)
        // Toolbar items keep their first measured width; a new identity re-measures.
        .fixedSize()
        .id(current.id)
    }
}

private struct RefreshUpdatesButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: CaskActionStyle.update.icon)
            }
        }
        .disabled(isRefreshing)
        .help("Refresh Updates")
        .accessibilityLabel("Refresh Updates")
    }
}

private struct GreedyButton: View {
    let isOn: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        let button = Button {
            onToggle(!isOn)
        } label: {
            Label("Greedy", systemImage: isOn ? "checkmark.circle.fill" : "circle")
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, CHSpace.toolbarLabelInset)
        }
        .help("Also list self-updating apps Homebrew cannot verify")
        .accessibilityAddTraits(isOn ? .isSelected : [])

        if isOn {
            button
                .buttonStyle(.borderedProminent)
                .tint(Color.chAccent.opacity(0.2))
                .foregroundStyle(Color.chAccent)
        } else {
            button
        }
    }
}

private struct UpdateAllButton: View {
    let count: Int
    let isUpdatingAll: Bool
    let isUpdatingHomebrew: Bool
    let onUpdateAll: () -> Void

    @State private var showsConfirmation = false

    private var isTinted: Bool {
        count > 0 && !isUpdatingAll && !isUpdatingHomebrew
    }

    var body: some View {
        let button = Button {
            showsConfirmation = true
        } label: {
            Group {
                if isUpdatingAll {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Updating…")
                    }
                } else {
                    Label("Update All", systemImage: LibraryItem.updates.icon)
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.horizontal, CHSpace.toolbarLabelInset)
        }
        .disabled(isUpdatingAll || isUpdatingHomebrew)
        .hoverHint(isUpdatingHomebrew ? String(localized: "Wait for the current action to finish.") : nil)
        .alert("Update All Apps?", isPresented: $showsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Update All", action: onUpdateAll)
        } message: {
            Text(.alertUpdateAllConfirmation(count))
        }

        if isTinted {
            button
                .buttonStyle(.borderedProminent)
                .tint(CaskActionStyle.update.background)
                .foregroundStyle(CaskActionStyle.update.foreground)
        } else {
            button
        }
    }
}
