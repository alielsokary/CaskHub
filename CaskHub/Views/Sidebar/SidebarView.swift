//
//  SidebarView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSelection
    var categoryService: CategoryService
    var updatesCount: Int = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List(selection: $selection) {
            Section("DISCOVER") {
                ForEach(DiscoverItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(SidebarSelection.discover(item))
                }
            }

            Section("LIBRARY") {
                ForEach(LibraryItem.allCases) { item in
                    libraryRow(item)
                        .tag(SidebarSelection.library(item))
                }
            }

            Section("CATEGORIES") {
                ForEach(categoryService.orderedCategories, id: \.id) { entry in
                    Label(entry.definition.displayName, systemImage: entry.definition.icon)
                        .tag(SidebarSelection.category(entry.id))
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func libraryRow(_ item: LibraryItem) -> some View {
        if item == .updates && updatesCount > 0 {
            HStack {
                Label(item.rawValue, systemImage: item.icon)
                Spacer()
                updatesBadge
            }
        } else {
            Label(item.rawValue, systemImage: item.icon)
        }
    }

    private var updatesBadge: some View {
        Text("\(updatesCount)")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(badgeForeground)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(badgeBackground))
    }

    private var badgeBackground: Color {
        colorScheme == .dark ? .white : .gray
    }

    private var badgeForeground: Color {
        colorScheme == .dark ? .black : .white
    }
}

#Preview {
    SidebarView(
        selection: .constant(.discover(.browse)),
        categoryService: {
            let service = CategoryService()
            service.loadCategories()
            return service
        }()
    )
    .frame(width: 200)
}
