//
//  SidebarView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarSection.allCases, id: \.self) { section in
                Section(section.rawValue) {
                    ForEach(SidebarItem.items(for: section)) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

#Preview {
    SidebarView(selection: .constant(.browse))
        .frame(width: 200)
}
