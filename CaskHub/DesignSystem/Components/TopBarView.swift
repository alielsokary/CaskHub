//
//  TopBarView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/07/2026.
//

import SwiftUI

struct TopBarView: View {
    let title: String
    let caskCount: Int
    @Binding var sortOption: SortOption
    var sortOptions: [SortOption] = SortOption.standard
    @Binding var viewMode: ViewMode
    @Binding var searchText: String
    var searchFocus: FocusState<Bool>.Binding
    var analyticsPeriod: AnalyticsPeriod?
    var onSelectPeriod: ((AnalyticsPeriod) -> Void)?
    var recentWindow: RecentlyAddedWindow?
    var onSelectWindow: ((RecentlyAddedWindow) -> Void)?
    var onUpdateAll: (() -> Void)?
    var isUpdatingAll = false
    var greedyUpdates: Bool?
    var onToggleGreedy: ((Bool) -> Void)?
    var showsSort = true
    var onSubmitSearch: (() -> Void)?

    @State private var showSortMenu = false
    @State private var showPeriodMenu = false

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(CHType.topBarTitle)
                .foregroundStyle(Color.chTextTitle)

            Text("\(caskCount.formatted()) casks")
                .font(CHType.countMeta)
                .foregroundStyle(Color.chTextMuted)

            Spacer(minLength: 10)

            if let greedyUpdates {
                greedyChip(isOn: greedyUpdates)
            }
            if onUpdateAll != nil {
                updateAllChip
            }
            if showsSort {
                sortChip
            }
            if let analyticsPeriod {
                periodChip(current: analyticsPeriod, options: AnalyticsPeriod.allCases, label: \.label) {
                    onSelectPeriod?($0)
                }
            }
            if let recentWindow {
                periodChip(current: recentWindow, options: RecentlyAddedWindow.allCases, label: \.label) {
                    onSelectWindow?($0)
                }
            }
            viewModeToggle
            searchField
        }
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 10))
        .glassPanel(radius: 999, surface: .chSurfaceToolbar)
    }

    // MARK: - Update All chip

    private var updateAllChip: some View {
        Button {
            onUpdateAll?()
        } label: {
            HStack(spacing: 6) {
                if isUpdatingAll {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: CaskActionStyle.update.icon)
                        .font(.system(size: 10, weight: .bold))
                }
                Text(isUpdatingAll ? "Updating…" : "Update All")
                    .font(CHType.button)
            }
            .foregroundStyle(Color.chActionUpdateFg)
            .padding(.vertical, 5)
            .padding(.horizontal, 14)
            .background(Capsule().fill(Color.chActionUpdateBg))
            .overlay(Capsule().strokeBorder(Color.chActionUpdateBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingAll)
    }

    // MARK: - Greedy updates chip

    private func greedyChip(isOn: Bool) -> some View {
        Button {
            onToggleGreedy?(!isOn)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .bold))
                Text("Greedy")
                    .font(CHType.button)
            }
            .foregroundStyle(isOn ? Color.chActionUpdateFg : Color.chTextTitle)
            .padding(.vertical, 5)
            .padding(.horizontal, 14)
            .background(Capsule().fill(isOn ? Color.chActionUpdateBg : Color.chSurfaceField))
            .overlay(Capsule().strokeBorder(
                isOn ? Color.chActionUpdateBorder : Color.chHairlineStrong, lineWidth: 1
            ))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Also list apps that update themselves (brew upgrade --greedy)")
    }

    // MARK: - Sort chip

    private var sortChip: some View {
        Button {
            showSortMenu.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .bold))
                Text(sortOption.rawValue)
                    .font(CHType.button)
            }
            .foregroundStyle(Color.chTextTitle)
            .padding(.vertical, 5)
            .padding(.horizontal, 14)
            .background(Capsule().fill(Color.chSurfaceField))
            .overlay(Capsule().strokeBorder(Color.chHairlineStrong, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSortMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sortOptions) { option in
                    menuRow(label: option.rawValue, isSelected: sortOption == option) {
                        if option != sortOption { Analytics.sortChanged(option) }
                        sortOption = option
                        showSortMenu = false
                    }
                }
            }
            .padding(8)
            .frame(width: 190)
        }
    }

    // MARK: - Time window chip (Top Charts period / Recently Added window)

    private func periodChip<Option: Identifiable & Equatable>(
        current: Option,
        options: [Option],
        label: KeyPath<Option, String>,
        onSelect: @escaping (Option) -> Void
    ) -> some View {
        Button {
            showPeriodMenu.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .bold))
                Text(current[keyPath: label])
                    .font(CHType.button)
            }
            .foregroundStyle(Color.chTextTitle)
            .padding(.vertical, 5)
            .padding(.horizontal, 14)
            .background(Capsule().fill(Color.chSurfaceField))
            .overlay(Capsule().strokeBorder(Color.chHairlineStrong, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPeriodMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options) { option in
                    menuRow(label: option[keyPath: label], isSelected: option == current) {
                        onSelect(option)
                        showPeriodMenu = false
                    }
                }
            }
            .padding(8)
            .frame(width: 150)
        }
    }

    private func menuRow(label: String, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            HStack {
                Text(label)
                    .font(isSelected ? CHType.navActive : CHType.navItem)
                    .foregroundStyle(isSelected ? Color.chActionInstallFg : Color.chTextNav)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.chActionInstallFg)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background {
                if isSelected {
                    Capsule().fill(Color.chActionInstallBg)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid / list toggle

    private var viewModeToggle: some View {
        HStack(spacing: 0) {
            segment(.grid, icon: "square.grid.2x2")
            segment(.list, icon: "list.bullet")
        }
        .padding(2)
        .background(Capsule().fill(Color.chSurfaceField))
        .overlay(Capsule().strokeBorder(Color.chHairlineStrong, lineWidth: 1))
    }

    private func segment(_ mode: ViewMode, icon: String) -> some View {
        Button {
            viewMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(viewMode == mode ? Color.chSegmentIcon : Color.chTextNav)
                .frame(width: 34, height: 22)
                .background {
                    if viewMode == mode {
                        Capsule().fill(Color.chTextTitle)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.chTextMuted)
            TextField("Search apps…", text: $searchText)
                .textFieldStyle(.plain)
                .font(CHType.field)
                .foregroundStyle(Color.chTextTitle)
                .focused(searchFocus)
                .onSubmit { onSubmitSearch?() }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.chTextMuted)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .frame(width: 240)
        .background(Capsule().fill(Color.chSurfaceField))
        .overlay(Capsule().strokeBorder(Color.chHairlineStrong, lineWidth: 1))
    }
}
