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
    @State private var viewModel = CaskCatalogViewModel()
    @State private var selectedItem: SidebarItem = .browse
    @State private var viewMode: ViewMode = .grid

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 300), spacing: 14)
    ]

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedItem)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            detailContent
                .navigationTitle(navigationTitle)
                .searchable(text: $viewModel.searchText, prompt: "Search apps...")
                .toolbar { toolbarItems }
        }
        .task {
            await viewModel.fetchCasks()
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if viewModel.isLoading {
            ProgressView("Loading casks...")
        } else if let error = viewModel.errorMessage {
            errorView(error)
        } else {
            switch viewMode {
            case .grid:
                gridView
            case .list:
                listView
            }
        }
    }

    private var navigationTitle: String {
        let count = viewModel.filteredCasks.count
        return "\(selectedItem.rawValue) (\(count) casks)"
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(viewModel.filteredCasks) { cask in
                    CaskCardView(
                        cask: cask,
                        downloads: viewModel.formattedDownloads(for: cask.token)
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - List View

    private var listView: some View {
        List(viewModel.filteredCasks) { cask in
            CaskRowView(
                cask: cask,
                downloads: viewModel.formattedDownloads(for: cask.token)
            )
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(error)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await viewModel.fetchCasks() }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            sortMenu
        }

        ToolbarItem(placement: .automatic) {
            Picker("View Mode", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                Image(systemName: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases) { option in
                Button {
                    viewModel.sortOption = option
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if viewModel.sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text("Sort by: \(viewModel.sortOption.rawValue)")
            }
        }
        .menuIndicator(.hidden)
    }
}

#Preview {
    ContentView()
}
