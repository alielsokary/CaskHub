//
//  ContentView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/02/2026.
//

import SwiftUI

enum ViewMode: String {
    case grid, list
}

struct ContentView: View {
    @State private var categoryService: CategoryService
    @State private var recentlyAddedTracker = RecentlyAddedTracker()
    @State private var viewModel: CaskCatalogViewModel
    @State private var imageCache = ImageCacheService()
    @State private var localHomebrew = LocalHomebrewService()
    @State private var selectedSidebar: SidebarSelection = .discover(.browse)
    @State private var viewMode: ViewMode = .grid
    @FocusState private var searchFocused: Bool
    @State private var showsResultsHeader = false

    // Fixed 4-column grid from the design mock (cards never reflow wider).
    private let columns = Array(
        repeating: GridItem(.fixed(CHSize.cardWidth), spacing: CHSpace.gridGap),
        count: 4
    )

    init() {
        let service = CategoryService()
        service.loadCategories()
        let tracker = RecentlyAddedTracker()
        let localHomebrewService = LocalHomebrewService()
        _categoryService = State(initialValue: service)
        _recentlyAddedTracker = State(initialValue: tracker)
        _localHomebrew = State(initialValue: localHomebrewService)
        _viewModel = State(initialValue: CaskCatalogViewModel(
            categoryService: service,
            recentlyAddedTracker: tracker,
            localHomebrew: localHomebrewService
        ))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selectedSidebar,
                categoryService: categoryService,
                updatesCount: viewModel.updatesCount,
                installedCount: localHomebrew.installedCasks.count,
                categoryCounts: viewModel.categoryCounts
            )
            // Min width sized so the longest category name never truncates.
            .navigationSplitViewColumnWidth(min: 245, ideal: 245, max: 300)
        } detail: {
            VStack(spacing: 0) {
                TopBarView(
                    title: sectionName,
                    caskCount: viewModel.filteredCasks.count,
                    sortOption: $viewModel.sortOption,
                    viewMode: $viewMode,
                    searchText: $viewModel.searchText,
                    searchFocus: $searchFocused,
                    analyticsPeriod: selectedSidebar == .discover(.topCharts) ? viewModel.analyticsPeriod : nil,
                    onSelectPeriod: { period in
                        Task { await viewModel.selectAnalyticsPeriod(period) }
                    },
                    // Sections have a fixed popularity order; sorting is a no-op there.
                    showsSort: selectedSidebar != .discover(.featured) && !showsBrowseSections,
                    onSubmitSearch: {
                        searchFocused = false
                        showsResultsHeader = !viewModel.searchText.isEmpty
                    }
                )
                // Never wider than the card grid below it, centered to match.
                .frame(maxWidth: CHSize.contentWidth)
                .padding(.horizontal, CHSpace.s5)
                .frame(maxWidth: .infinity)
                .padding(.top, CHSpace.s4)

                if showsResultsHeader {
                    Text("Results for “\(viewModel.searchText)”")
                        .font(CHType.section)
                        .foregroundStyle(Color.chTextTitle)
                        .frame(maxWidth: CHSize.contentWidth, alignment: .leading)
                        .padding(.horizontal, CHSpace.s5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, CHSpace.s4)
                }

                detailContent
            }
            // The hidden title bar still reserves toolbar height as safe area;
            // ignore it so the top bar sits 16pt from the window edge.
            .ignoresSafeArea(.container, edges: .top)
        }
        .overlay {
            // Invisible ⌘F target: focuses the custom search field.
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBarView(
                caskCount: viewModel.filteredCasks.count,
                updatesCount: viewModel.updatesCount,
                brewVersion: localHomebrew.brewVersion
            )
        }
        .containerBackground(for: .window) {
            WindowBackdrop()
        }
        .tint(Color.chTerracotta)
        .environment(imageCache)
        .environment(localHomebrew)
        .task {
            async let catalog: Void = viewModel.fetchCasks()
            async let local: Void = localHomebrew.refresh()
            async let categories: Void = categoryService.refreshFromRemote()
            _ = await (catalog, local, categories)
        }
        .onChange(of: selectedSidebar) { _, newValue in
            viewModel.selectedSidebar = newValue
            if newValue == .discover(.topCharts) {
                // Fetch the current period's data if it hasn't loaded yet.
                Task { await viewModel.selectAnalyticsPeriod(viewModel.analyticsPeriod) }
            }
        }
        .onChange(of: viewModel.searchText) { _, newValue in
            if newValue.isEmpty {
                // Only drop focus when clearing a submitted search — while
                // still composing (backspaced to empty), keep the field active.
                if showsResultsHeader { searchFocused = false }
                showsResultsHeader = false
            }
        }
        .onAppear {
            // AppKit hands the window's initial key focus to the first text
            // field; take it back so the search field only activates via ⌘F.
            DispatchQueue.main.async { searchFocused = false }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if viewModel.isLoading {
            ProgressView("Loading casks…")
                .font(CHType.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            errorView(error)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewMode {
            case .grid:
                gridView
            case .list:
                listView
            }
        }
    }

    private var sectionName: String {
        switch selectedSidebar {
        case .discover(let item): return item.rawValue
        case .library(let item): return item.rawValue
        case .category(let categoryID): return categoryService.displayName(for: categoryID)
        }
    }

    /// House pick: shown on Browse when not searching.
    private var heroCask: Cask? {
        guard showsBrowseSections else { return nil }
        return viewModel.filteredCasks.first
    }

    /// Browse shows titled shelves instead of the flat grid — unless searching,
    /// where a flat result grid is more useful. List mode stays a flat list.
    private var showsBrowseSections: Bool {
        selectedSidebar == .discover(.browse)
            && viewModel.searchText.isEmpty
            && viewMode == .grid
    }

    private func categoryInfo(for cask: Cask) -> (id: String, name: String)? {
        guard let id = categoryService.category(for: cask.token) else { return nil }
        return (id, categoryService.displayName(for: id))
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CHSpace.s4) {
                if let hero = heroCask {
                    HeroCard(
                        cask: hero,
                        downloads: viewModel.formattedDownloads(for: hero.token),
                        categoryName: categoryInfo(for: hero)?.name
                    )
                }
                if showsBrowseSections {
                    ForEach(viewModel.browseSections) { section in
                        browseSectionView(section)
                    }
                } else {
                    caskGrid(viewModel.filteredCasks)
                }
            }
            .frame(width: CHSize.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, CHSpace.s4)
        }
        .contentMargins(.bottom, 44, for: .scrollContent)
        .scrollContentBackground(.hidden)
        // Recreate the scroll view per sidebar selection so navigating
        // (View All, sidebar clicks) always lands at the top.
        .id(selectedSidebar)
    }

    private func caskGrid(_ casks: [Cask]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: CHSpace.gridGap) {
            ForEach(casks) { cask in
                CaskCardView(
                    cask: cask,
                    downloads: viewModel.formattedDownloads(for: cask.token),
                    category: categoryInfo(for: cask),
                    onSelectCategory: { selectedSidebar = .category($0) }
                )
            }
        }
    }

    private func browseSectionView(_ section: BrowseSection) -> some View {
        VStack(alignment: .leading, spacing: CHSpace.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(CHType.section)
                    .foregroundStyle(Color.chTextTitle)
                Spacer()
                Button {
                    selectedSidebar = section.destination
                } label: {
                    Text("View All")
                        .font(CHType.button)
                        .foregroundStyle(Color.chTextBrand)
                }
                .buttonStyle(.plain)
            }
            caskGrid(section.casks)
        }
        .padding(.top, CHSpace.s3)
    }

    // MARK: - List View

    private var listView: some View {
        List(viewModel.filteredCasks) { cask in
            CaskRowView(
                cask: cask,
                downloads: viewModel.formattedDownloads(for: cask.token)
            )
        }
        .contentMargins(.bottom, 44, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .id(selectedSidebar)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            BarrelMark()
                .frame(width: 56, height: 56)
                .opacity(0.6)
            Text(error)
                .font(CHType.body)
                .foregroundStyle(Color.chTextBody)
            ActionCapsuleButton(action: .update, fullWidth: false) {
                Task { await viewModel.fetchCasks() }
            }
        }
    }
}

#Preview {
    ContentView()
}
