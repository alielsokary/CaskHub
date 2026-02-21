//
//  ContentView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 08/02/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = CaskCatalogViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading casks...")
                } else if let error = viewModel.errorMessage {
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
                } else {
                    List(viewModel.filteredCasks) { cask in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cask.displayName)
                                    .font(.headline)
                                if let desc = cask.desc {
                                    Text(desc)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("v\(cask.version)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                if let downloads = viewModel.formattedDownloads(for: cask.token) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.down.circle")
                                        Text(downloads)
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("CaskHub (\(viewModel.filteredCasks.count) casks)")
            .searchable(text: $viewModel.searchText, prompt: "Search apps...")
            .toolbar {
                ToolbarItem(placement: .automatic) {
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
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .menuIndicator(.hidden)
                }
            }
        }
        .task {
            await viewModel.fetchCasks()
        }
    }
}

#Preview {
    ContentView()
}
