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
    @AppStorage("viewMode") var viewMode: ViewMode = .grid
    @FocusState private var searchFocused: Bool
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var showsResultsHeader = false
    @State private var searchSignalTask: Task<Void, Never>?

    let columns = Array(
        repeating: GridItem(.fixed(CHSize.cardWidth), spacing: CHSpace.gridGap),
        count: 4
    )

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
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
                if isUtilityPage {
                    utilityTopBar
                        .frame(maxWidth: CHSize.contentWidth)
                        .padding(.horizontal, CHSpace.s5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CHSpace.s4)
                } else {
                    catalogTopBar
                        .frame(maxWidth: CHSize.contentWidth)
                        .padding(.horizontal, CHSpace.s5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CHSpace.s4)
                }

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
        .focusedSceneValue(\.catalogViewMode, $viewMode)
        .focusedSceneValue(\.sidebarVisibility, $sidebarVisibility)
        .windowToolbarFullScreenVisibility(.onHover)
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

    // MARK: - Top Bar

    private var catalogTopBar: some View {
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
    }

    private var utilityTopBar: some View {
        UtilityTopBar(
            title: sectionName,
            summary: selectedSidebar == .shelfSetup
                ? String(localized: .shelfSetupIgnoredCount(viewModel.adoptIgnoredCasks.count))
                : nil
        )
    }

    private var isUtilityPage: Bool {
        selectedSidebar == .shelfSetup || selectedSidebar == .maintenance
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSidebar {
        case .shelfSetup:
            ShelfSetupView(viewModel: viewModel)
        case .maintenance:
            MaintenancePlaceholderView()
        default:
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
    }

    private var sectionName: String {
        switch selectedSidebar {
        case let .discover(item): return item.rawValue
        case let .library(item): return item.rawValue
        case .shelfSetup: return String(localized: .sidebarShelfSetup)
        case .maintenance: return String(localized: .sidebarHealth)
        case let .category(categoryID): return categoryService.displayName(for: categoryID)
        }
    }

    var selectedSidebar: SidebarSelection {
        viewModel.selectedSidebar
    }

    var heroCask: Cask? {
        guard showsBrowseSections else { return nil }
        return viewModel.filteredCasks.first
    }

    // Raw searchText would swap layout before results apply and flash a stale grid.
    var showsBrowseSections: Bool {
        selectedSidebar == .discover(.browse)
            && viewModel.appliedSearchText.isEmpty
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

    func categoryInfo(for cask: Cask) -> CaskCategoryPresentation? {
        viewModel.categoryPresentation(for: cask)
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
