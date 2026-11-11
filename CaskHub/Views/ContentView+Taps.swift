//
//  ContentView+Taps.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import SwiftUI

enum TapDialog: Identifiable, Equatable {
    case add
    case remove(String)

    var id: String {
        switch self {
        case .add: "add"
        case let .remove(name): "remove.\(name)"
        }
    }
}

extension ContentView {
    var isTapsPage: Bool {
        !Self.showsTapBadges(on: selectedSidebar)
    }

    static func showsTapBadges(on selection: SidebarSelection) -> Bool {
        switch selection {
        case .library(.taps), .tap: false
        default: true
        }
    }

    @ViewBuilder
    var tapsContent: some View {
        if localHomebrew.tapIndex.taps.isEmpty {
            TapsEmptyStateView { tapDialog = .add }
        } else {
            VStack(alignment: .leading, spacing: CHSpace.s4) {
                ForEach(viewModel.tapSections) { section in
                    tapSectionView(section)
                }
            }
            .frame(maxWidth: catalogWidth, alignment: .leading)
            .padding(.horizontal, CHSize.catalogInset)
            .frame(maxWidth: .infinity)
        }
    }

    var tapsSummary: String {
        let count = viewModel.tapSections.reduce(0) { $0 + viewModel.tapCasks(in: $1.id).count }
        return String(localized: "\(count) casks")
    }

    private func tapSectionView(_ section: TapSection) -> some View {
        let name = section.tap.name
        let hasMore = viewModel.tapHasMore(name)
        return VStack(alignment: .leading, spacing: CHSpace.s3) {
            TapSectionHeader(
                tap: section.tap,
                onViewAll: hasMore ? { viewModel.selectedSidebar = .tap(name) } : nil,
                onRemove: { tapDialog = .remove(name) }
            )
            tapItems(casks: section.casks, formulae: section.formulae)
        }
        .padding(.top, CHSpace.s3)
    }

    @ViewBuilder
    func tapItems(casks: [Cask], formulae: [TapFormula]) -> some View {
        switch viewMode {
        case .grid:
            if !casks.isEmpty || !formulae.isEmpty {
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
                    ForEach(formulae) { FormulaCardView(formula: $0) }
                }
            }
        case .list:
            LazyVStack(spacing: 0) {
                caskList(casks)
                ForEach(formulae) { formula in
                    FormulaRowView(formula: formula)
                        .padding(.vertical, 6)
                    Color.chHairline.frame(height: 1)
                }
            }
        }
    }

    func refreshTaps() {
        isRefreshingTaps = true
        Task {
            await viewModel.updateTaps(maxAge: 0)
            isRefreshingTaps = false
        }
    }
}

/// Add/remove tap sheets and the first-install trust alert, for every install entry point in the window.
struct TapPresentation: ViewModifier {
    @Binding var dialog: TapDialog?
    let viewModel: CaskCatalogViewModel

    @Environment(LocalHomebrewService.self) private var localHomebrew

    func body(content: Content) -> some View {
        let pending = localHomebrew.pendingTrustInstall
        content
            .sheet(item: $dialog) { dialog in
                switch dialog {
                case .add:
                    AddTapSheet(viewModel: viewModel, model: AddTapModel())
                case let .remove(name):
                    RemoveTapDialog(viewModel: viewModel, tapName: name, preview: nil)
                }
            }
            .alert(
                Text(verbatim: pending.map { TrustInstallPrompt(cask: $0).title } ?? ""),
                isPresented: Binding(get: { pending != nil }, set: { _ in }),
                presenting: pending
            ) { cask in
                Button("Cancel", role: .cancel) { localHomebrew.send(.cancelTrustedInstall) }
                Button("Install") { localHomebrew.send(.confirmTrustedInstall(cask)) }
            } message: { cask in
                Text(verbatim: TrustInstallPrompt(cask: cask).message)
            }
    }
}
