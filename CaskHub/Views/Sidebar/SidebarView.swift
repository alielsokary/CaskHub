//
//  SidebarView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import SwiftUI

struct SidebarView: View {
    static let showAdoptKey = "showAdoptApps"

    @Binding var selection: SidebarSelection
    @AppStorage(Self.showAdoptKey) private var showAdoptApps = true
    var categoryService: CategoryService
    var updatesCount: Int = 0
    var installedCount: Int = 0
    var adoptableCount: Int = 0
    var categoryCounts: [String: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandWordmark()
                .padding(.horizontal, 18)
                .padding(.top, 38)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("DISCOVER")
                    ForEach(DiscoverItem.allCases) { item in
                        row(.discover(item), title: item.rawValue, icon: item.icon)
                    }

                    sectionHeader("LIBRARY")
                    row(.library(.installed), title: "Installed", icon: LibraryItem.installed.icon, count: installedCount)
                    row(.library(.updates), title: "Updates", icon: LibraryItem.updates.icon, badge: updatesCount)
                    if showAdoptApps {
                        row(.library(.adopt), title: LibraryItem.adopt.rawValue, icon: LibraryItem.adopt.icon, count: adoptableCount)
                    }

                    sectionHeader("CATEGORIES")
                    ForEach(categoryService.orderedCategories, id: \.id) { entry in
                        row(
                            .category(entry.id),
                            title: entry.definition.displayName,
                            icon: entry.definition.icon,
                            count: categoryCounts[entry.id]
                        )
                    }
                }
                .padding(.horizontal, 10)
            }
            .contentMargins(.bottom, 44, for: .scrollContent)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: showAdoptApps) { _, shown in
            if !shown, selection == .library(.adopt) {
                selection = .library(.installed)
            }
        }
    }

    // MARK: - Rows

    private func row(
        _ tag: SidebarSelection,
        title: String,
        icon: String,
        count: Int? = nil,
        badge: Int = 0
    ) -> some View {
        let isSelected = selection == tag
        return Button {
            selection = tag
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.chActionInstallFg : Color.chTextMuted)
                    .frame(width: 16)
                Text(title)
                    .font(isSelected ? CHType.navActive : CHType.navItem)
                    .foregroundStyle(isSelected ? Color.chActionInstallFg : Color.chTextNav)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if badge > 0 {
                    CountBadge(count: badge)
                } else if let count {
                    Text("\(count)")
                        .font(CHType.statusMono)
                        .foregroundStyle(isSelected ? Color.chActionInstallFg : Color.chTextFaint)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.chActionInstallBg)
                        .overlay(Capsule().strokeBorder(Color.chHairlineStrong, lineWidth: 1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(CHType.label)
            .kerning(CHType.trackingLabel)
            .foregroundStyle(Color.chTextMuted)
            .padding(.top, 16)
            .padding(.horizontal, 10)
            .padding(.bottom, 5)
    }
}

#Preview {
    SidebarView(
        selection: .constant(.discover(.browse)),
        categoryService: {
            let service = CategoryService()
            service.loadCategories()
            return service
        }(),
        updatesCount: 1,
        installedCount: 42
    )
    .frame(width: 226, height: 700)
    .background(WindowBackdrop())
}
