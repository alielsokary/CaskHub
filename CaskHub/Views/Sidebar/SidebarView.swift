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
                    Label(item.rawValue, systemImage: item.icon)
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
