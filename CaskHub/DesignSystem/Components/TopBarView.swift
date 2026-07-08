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
    @Binding var viewMode: ViewMode
    @Binding var searchText: String
    var searchFocus: FocusState<Bool>.Binding
    /// Non-nil on Top Charts: shows the analytics period chip next to the sort chip.
    var analyticsPeriod: AnalyticsPeriod?
    var onSelectPeriod: ((AnalyticsPeriod) -> Void)?
    /// Hidden on Featured — that list is curated, sorting doesn't apply.
    var showsSort = true

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
                periodChip(analyticsPeriod)
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
                ForEach(SortOption.allCases) { option in
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

    // MARK: - Top Charts period chip

    private func periodChip(_ period: AnalyticsPeriod) -> some View {
        Button {
            showPeriodMenu.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .bold))
                Text(period.label)
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
                ForEach(AnalyticsPeriod.allCases) { option in
                    periodMenuRow(option, current: period)
                }
            }
            .padding(8)
            .frame(width: 150)
        }
    }

    private func periodMenuRow(_ option: AnalyticsPeriod, current: AnalyticsPeriod) -> some View {
        let isSelected = option == current
        return Button {
            onSelectPeriod?(option)
            showPeriodMenu = false
        } label: {
            HStack {
                Text(option.label)
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
            Keycap(symbol: "⌘F")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .frame(width: 240)
        .background(Capsule().fill(Color.chSurfaceField))
        .overlay(Capsule().strokeBorder(Color.chHairlineStrong, lineWidth: 1))
    }
}
