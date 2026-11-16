//
//  ContentView+Catalog.swift
//  CaskHub
//
//  Created by Ali Elsokary on 10/08/2026.
//

import SwiftUI

// MARK: - Grid, List & Error Views

extension ContentView {
    var columns: [GridItem] {
        [GridItem(.adaptive(minimum: CHSize.minimumCardWidth, maximum: CHSize.maximumCardWidth),
                  spacing: CHSpace.gridGap)]
    }

    var catalogView: some View {
        ScrollView {
            catalogContent
        }
        .contentMargins(.top, CHSpace.belowToolbar, for: .scrollContent)
        .toolbarScrollEdge()
        .contentMargins(.bottom, 44, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .modifier(ResetScrollOnChange(trigger: selectedSidebar))
    }

    @ViewBuilder
    var catalogContent: some View {
        if selectedSidebar == .library(.taps) {
            tapsContent
        } else {
            switch viewMode {
            case .grid:
                gridContent
            case .list:
                listContent
            }
        }
    }

    private var externallyManagedSection: some View {
        catalogSectionView(
            String(localized: "Managed Outside Homebrew"),
            casks: viewModel.filteredExternallyManagedCasks,
            destination: nil
        )
    }

    var gridContent: some View {
        Group {
            if showsBrowseSections {
                // Lazy so off-screen shelves aren't built and measured on launch or when search clears.
                LazyVStack(alignment: .leading, spacing: CHSpace.s4) {
                    if let hero = heroCask {
                        HeroCard(
                            cask: hero,
                            downloads: viewModel.formattedDownloads(for: hero.reference),
                            categoryName: categoryInfo(for: hero)?.mainName,
                            localState: viewModel.localState(for: hero)
                        )
                    }
                    ForEach(viewModel.browseSections) { section in
                        browseSectionView(section)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: CHSpace.s4) {
                    caskGrid(viewModel.displayedCasks, showsReveal: true)
                    if showsExternallyManagedSection {
                        externallyManagedSection
                    }
                }
            }
        }
        .frame(maxWidth: catalogWidth, alignment: .leading)
        .padding(.horizontal, CHSize.catalogInset)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    var listContent: some View {
        if showsBrowseSections {
            LazyVStack(alignment: .leading, spacing: CHSpace.s4) {
                if let hero = heroCask {
                    VStack(spacing: 0) {
                        CaskRowView(
                            cask: hero,
                            downloads: viewModel.formattedDownloads(for: hero.reference),
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
            .frame(maxWidth: catalogWidth, alignment: .leading)
            .padding(.horizontal, CHSize.catalogInset)
            .frame(maxWidth: .infinity)
        } else {
            LazyVStack(spacing: 0) {
                caskList(viewModel.displayedCasks)
                if viewModel.hasMoreToReveal {
                    RevealSentinel { viewModel.revealMore() }
                }
                if showsExternallyManagedSection {
                    externallyManagedSection
                        .padding(.top, CHSpace.s4)
                }
            }
            .frame(maxWidth: catalogWidth)
            .padding(.horizontal, CHSize.catalogInset)
            .frame(maxWidth: .infinity)
        }
    }

    func caskList(_ casks: [Cask]) -> some View {
        ForEach(casks) { cask in
            CaskRowView(
                cask: cask,
                downloads: viewModel.formattedDownloads(for: cask.reference),
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
                    downloads: viewModel.formattedDownloads(for: cask.reference),
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
        catalogSectionView(section.title, casks: section.casks, destination: section.destination)
    }

    private func catalogSectionView(
        _ title: String,
        casks: [Cask],
        destination: SidebarSelection?
    ) -> some View {
        VStack(alignment: .leading, spacing: CHSpace.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(CHType.section)
                    .foregroundStyle(Color.chTextTitle)
                Spacer()
                if let destination {
                    Button {
                        Analytics.viewAllTapped(to: destination)
                        viewModel.selectedSidebar = destination
                    } label: {
                        Text("View All")
                            .font(CHType.button)
                            .foregroundStyle(Color.chTextBrand)
                    }
                    .buttonStyle(.plain)
                }
            }
            switch viewMode {
            case .grid:
                caskGrid(casks)
            case .list:
                LazyVStack(spacing: 0) {
                    caskList(casks)
                }
            }
        }
        .padding(.top, CHSpace.s3)
    }

    var showsExternallyManagedSection: Bool {
        selectedSidebar == .library(.installed)
            && showExternallyManagedApps
            && !viewModel.filteredExternallyManagedCasks.isEmpty
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
