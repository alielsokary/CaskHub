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
    @Bindable var viewModel: CaskCatalogViewModel
    @Environment(CategoryService.self) private var categoryService
    @Environment(LocalHomebrewService.self) private var localHomebrew
    @AppStorage("viewMode") private var viewMode: ViewMode = .grid
    @FocusState private var searchFocused: Bool
    @State private var showsResultsHeader = false
    @State private var searchSignalTask: Task<Void, Never>?

    private let columns = Array(
        repeating: GridItem(.fixed(CHSize.cardWidth), spacing: CHSpace.gridGap),
        count: 4
    )

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: Binding(
                    get: { viewModel.selectedSidebar },
                    set: { viewModel.selectedSidebar = $0 }
                ),
                categoryService: categoryService,
                updatesCount: viewModel.updatesCount,
                installedCount: viewModel.installedCount,
                adoptableCount: viewModel.adoptableCasks.count,
                categoryCounts: viewModel.categoryCounts
            )
            .navigationSplitViewColumnWidth(min: 245, ideal: 245, max: 300)
        } detail: {
            VStack(spacing: 0) {
                TopBarView(
                    title: sectionName,
                    caskCount: viewModel.filteredCasks.count,
                    sortOption: $viewModel.sortOption,
                    sortOptions: sortOptions,
                    viewMode: $viewMode,
                    searchText: $viewModel.searchText,
                    searchFocus: $searchFocused,
                    analyticsPeriod: selectedSidebar == .discover(.topCharts) ? viewModel.analyticsPeriod : nil,
                    onSelectPeriod: { period in
                        Analytics.topChartsPeriodChanged(period)
                        Task { await viewModel.selectAnalyticsPeriod(period) }
                    },
                    recentWindow: selectedSidebar == .discover(.recentlyAdded) ? viewModel.recentlyAddedWindow : nil,
                    onSelectWindow: {
                        Analytics.recentWindowChanged($0)
                        viewModel.selectRecentlyAddedWindow($0)
                    },
                    onUpdateAll: selectedSidebar == .library(.updates) && viewModel.updatesCount > 0
                        ? {
                            let tokens = viewModel.updatableCasks.map(\.token)
                            Analytics.updateAllTapped(count: tokens.count)
                            localHomebrew.send(.updateAll(tokens: tokens))
                        }
                        : nil,
                    updateAllCount: viewModel.updatesCount,
                    isUpdatingAll: localHomebrew.isUpdatingAll,
                    greedyUpdates: selectedSidebar == .library(.updates) ? localHomebrew.greedyUpdates : nil,
                    onToggleGreedy: { enabled in
                        Analytics.greedyUpdatesChanged(enabled)
                        localHomebrew.setGreedyUpdates(enabled)
                    },
                    showsSort: selectedSidebar != .discover(.featured) && !showsBrowseSections,
                    onSubmitSearch: {
                        searchFocused = false
                        showsResultsHeader = !viewModel.searchText.isEmpty
                    }
                )
                .frame(maxWidth: CHSize.contentWidth)
                .padding(.horizontal, CHSpace.s5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CHSpace.s4)

                if showsResultsHeader {
                    Text("Results for “\(viewModel.searchText)”")
                        .font(CHType.section)
                        .foregroundStyle(Color.chTextTitle)
                        .frame(maxWidth: CHSize.contentWidth, alignment: .leading)
                        .padding(.horizontal, CHSpace.s5)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, CHSpace.s4)
                }

                detailContent
                    .environment(\.isAdoptPage, selectedSidebar == .library(.adopt))
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .overlay {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ObservedStatusBarView(
                caskCount: viewModel.casks.count,
                brewVersion: localHomebrew.brewVersion,
                caskFlowRelease: categoryService.releaseTag
            )
        }
        .containerBackground(for: .window) {
            WindowBackdrop()
        }
        .tint(Color.chTerracotta)
        .task {
            await viewModel.load()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            Task { await viewModel.refreshIfStale() }
        }
        .onChange(of: viewModel.selectedSidebar) { _, newValue in
            Analytics.pageOpened(newValue)
            if newValue == .discover(.topCharts) {
                Task { await viewModel.selectAnalyticsPeriod(viewModel.analyticsPeriod) }
            }
        }
        .onChange(of: viewMode) { _, newValue in
            Analytics.viewModeChanged(newValue)
        }
        .onChange(of: viewModel.searchText) { _, newValue in
            searchSignalTask?.cancel()
            if !newValue.isEmpty {
                searchSignalTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    Analytics.searchPerformed(
                        query: newValue,
                        results: viewModel.filteredCasks.count
                    )
                }
            }
            if newValue.isEmpty {
                if showsResultsHeader { searchFocused = false }
                showsResultsHeader = false
            }
        }
        .onAppear {
            DispatchQueue.main.async { searchFocused = false }
        }
        .modifier(ResignFocusOnOutsideClick(
            isFocused: { searchFocused },
            resign: { searchFocused = false }
        ))
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
            catalogView
        }
    }

    private var sectionName: String {
        switch selectedSidebar {
        case let .discover(item): return item.rawValue
        case let .library(item): return item.rawValue
        case let .category(categoryID): return categoryService.displayName(for: categoryID)
        }
    }

    private var selectedSidebar: SidebarSelection {
        viewModel.selectedSidebar
    }

    private var heroCask: Cask? {
        guard showsBrowseSections else { return nil }
        return viewModel.filteredCasks.first
    }

    // Gates on the debounced value so the layout swaps in the same frame as the
    // filtered results — raw searchText would flash an unfiltered grid first.
    private var showsBrowseSections: Bool {
        selectedSidebar == .discover(.browse)
            && viewModel.appliedSearchText.isEmpty
            && viewMode == .grid
    }

    private var sortOptions: [SortOption] {
        switch selectedSidebar {
        case .library(.installed):
            return SortOption.installed
        case .discover(.recentlyAdded):
            return SortOption.standard + [.oldest, .newest]
        default:
            return SortOption.standard
        }
    }

    private func categoryInfo(for cask: Cask) -> CaskCategoryPresentation? {
        viewModel.categoryPresentation(for: cask)
    }
}

// MARK: - Grid, List & Error Views

private extension ContentView {
    var catalogView: some View {
        ScrollView {
            catalogContent
        }
        .contentMargins(.bottom, 44, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .modifier(ResetScrollOnChange(trigger: selectedSidebar))
    }

    @ViewBuilder
    var catalogContent: some View {
        switch viewMode {
        case .grid:
            gridContent
        case .list:
            listContent
        }
    }

    var gridContent: some View {
        VStack(alignment: .leading, spacing: CHSpace.s4) {
            if let hero = heroCask {
                HeroCard(
                    cask: hero,
                    downloads: viewModel.formattedDownloads(for: hero.token),
                    categoryName: categoryInfo(for: hero)?.mainName,
                    localState: viewModel.localState(for: hero)
                )
            }
            if showsBrowseSections {
                ForEach(viewModel.browseSections) { section in
                    browseSectionView(section)
                }
            } else {
                caskGrid(viewModel.displayedCasks, showsReveal: true)
            }
        }
        .frame(width: CHSize.contentWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    var listContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.displayedCasks) { cask in
                CaskRowView(
                    cask: cask,
                    downloads: viewModel.formattedDownloads(for: cask.token),
                    category: categoryInfo(for: cask),
                    localState: viewModel.localState(for: cask)
                )
                .padding(.vertical, 6)

                Color.chHairline
                    .frame(height: 1)
            }
            if viewModel.hasMoreToReveal {
                RevealSentinel { viewModel.revealMore() }
            }
        }
        .frame(width: CHSize.contentWidth)
        .frame(maxWidth: .infinity)
    }

    // showsReveal must stay off for the bounded browse-section shelves — their
    // sentinels would fire against the global reveal state, not their own casks.
    func caskGrid(_ casks: [Cask], showsReveal: Bool = false) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: CHSpace.gridGap) {
            ForEach(casks) { cask in
                CaskCardView(
                    cask: cask,
                    downloads: viewModel.formattedDownloads(for: cask.token),
                    category: categoryInfo(for: cask),
                    onSelectCategory: { viewModel.selectedSidebar = .category($0) },
                    localState: viewModel.localState(for: cask)
                )
            }
            if showsReveal && viewModel.hasMoreToReveal {
                RevealSentinel { viewModel.revealMore() }
            }
        }
    }

    func browseSectionView(_ section: BrowseSection) -> some View {
        VStack(alignment: .leading, spacing: CHSpace.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(CHType.section)
                    .foregroundStyle(Color.chTextTitle)
                Spacer()
                Button {
                    Analytics.viewAllTapped(to: section.destination)
                    viewModel.selectedSidebar = section.destination
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

    // MARK: - Error View

    func errorView(_ error: String) -> some View {
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

// MARK: - Outside-Click Focus Handling

struct ResignFocusOnOutsideClick: ViewModifier {
    let isFocused: () -> Bool
    let resign: () -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                    if isFocused(),
                       let frameView = event.window?.contentView?.superview,
                       !(frameView.hitTest(event.locationInWindow) is NSTextView) {
                        resign()
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

#Preview {
    let categories = CategoryService()
    let recent = RecentlyAddedService()
    let homebrew = LocalHomebrewService()
    ContentView(viewModel: CaskCatalogViewModel(
        apiClient: BrewAPIClient(),
        categoryService: categories,
        recentlyAdded: recent,
        localHomebrew: homebrew
    ))
    .environment(categories)
    .environment(recent)
    .environment(homebrew)
    .environment(ImageCacheService())
}
