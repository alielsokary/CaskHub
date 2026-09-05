//
//  ContentView+Catalog.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/08/2026.
//

import SwiftUI

// MARK: - Grid, List & Error Views

extension ContentView {
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
        .padding(.horizontal, CHSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var listContent: some View {
        if showsBrowseSections {
            VStack(alignment: .leading, spacing: CHSpace.s4) {
                if let hero = heroCask {
                    VStack(spacing: 0) {
                        CaskRowView(
                            cask: hero,
                            downloads: viewModel.formattedDownloads(for: hero.token),
                            category: categoryInfo(for: hero),
                            localState: viewModel.localState(for: hero),
                            eyebrow: "✷ HOUSE PICK"
                        )
                        .padding(.vertical, 6)

                        Color.chHairline
                            .frame(height: 1)
                    }
                }
                ForEach(viewModel.browseSections) { section in
                    browseSectionView(section)
                }
            }
            .padding(.horizontal, CHSpace.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVStack(spacing: 0) {
                caskList(viewModel.displayedCasks)
                if viewModel.hasMoreToReveal {
                    RevealSentinel { viewModel.revealMore() }
                }
            }
            .padding(.horizontal, CHSpace.s5)
            .frame(maxWidth: .infinity)
        }
    }

    func caskList(_ casks: [Cask]) -> some View {
        ForEach(casks) { cask in
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
    }

    // showsReveal stays off for browse shelves — global reveal state, not theirs.
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
            switch viewMode {
            case .grid:
                caskGrid(section.casks)
            case .list:
                LazyVStack(spacing: 0) {
                    caskList(section.casks)
                }
            }
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
