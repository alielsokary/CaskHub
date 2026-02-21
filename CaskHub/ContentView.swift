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
                    List(viewModel.casks) { cask in
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
                            Text("v\(cask.version)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("CaskHub (\(viewModel.casks.count) casks)")
        }
        .task {
            await viewModel.fetchCasks()
        }
    }
}

#Preview {
    ContentView()
}
