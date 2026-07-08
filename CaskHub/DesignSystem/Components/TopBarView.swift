//
//  TopBarView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/07/2026.
//

import SwiftUI

/// Floating glass pill top bar (design option 3b/3c): screen title, cask count,
/// sort chip, grid/list toggle and the search field with its ⌘F keycap.
struct TopBarView: View {
    let title: String
    let caskCount: Int
    @Binding var sortOption: SortOption
    /// Sort choices for the current page (Recently Added adds Newest/Oldest).
    var sortOptions: [SortOption] = SortOption.standard
    @Binding var viewMode: ViewMode
    @Binding var searchText: String
    var searchFocus: FocusState<Bool>.Binding
    /// Non-nil on Top Charts: shows the analytics period chip next to the sort chip.
    var analyticsPeriod: AnalyticsPeriod?
    var onSelectPeriod: ((AnalyticsPeriod) -> Void)?
    /// Non-nil on Recently Added: shows the 30/60/90-day window chip.
    var recentWindow: RecentlyAddedWindow?
    var onSelectWindow: ((RecentlyAddedWindow) -> Void)?
    /// Hidden on Featured — that list is curated, sorting doesn't apply.
    var showsSort = true
    /// Called when the user presses Return in the search field.
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

    // MARK: - Sort chip

    // Custom popover instead of Menu: NSMenu items ignore custom fonts, and the
    // design system's Nunito must apply to the dropdown too.
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
                    sortMenuRow(option)
                }
            }
            .padding(8)
            .frame(width: 190)
        }
    }

    private func sortMenuRow(_ option: SortOption) -> some View {
        let isSelected = sortOption == option
        return Button {
            sortOption = option
            showSortMenu = false
        } label: {
            HStack {
                Text(option.rawValue)
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

    // MARK: - Time window chip (Top Charts period / Recently Added window)

    // Only one window chip is ever visible at a time, so both share the
    // single showPeriodMenu state.
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
                    periodMenuRow(label: option[keyPath: label], isSelected: option == current) {
                        onSelect(option)
                    }
                }
            }
            .padding(8)
            .frame(width: 150)
        }
    }

    private func periodMenuRow(label: String, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        Button {
            onSelect()
            showPeriodMenu = false
        } label: {
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
