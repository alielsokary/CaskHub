//
//  SidebarView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import SwiftUI

struct SidebarView: View {
    static let showAdoptKey = "showAdoptApps"
    static let showTapsKey = "showTaps"

    @Binding var selection: SidebarSelection
    @AppStorage(Self.showAdoptKey) private var showAdoptApps = true
    @AppStorage(Self.showTapsKey) private var showTaps = true
    var categoryService: CategoryService
    var updatesCount: Int = 0
    var installedCount: Int = 0
    var adoptableCount: Int = 0
    var savedCount: Int = 0
    let tapsCount: Int
    var categoryCounts: [String: Int] = [:]

    @Environment(\.catalogTextScale) private var textScale

    private var typography: CHType.Catalog { CHType.Catalog(scale: textScale) }

    private var brandTopPadding: CGFloat {
        if #available(macOS 27, *) {
            return 50
        }
        return 40
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandWordmark()
                .padding(.horizontal, 18)
                .padding(.top, brandTopPadding)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("DISCOVER")
                    ForEach(DiscoverItem.allCases) { item in
                        row(.discover(item), title: item.title, icon: item.icon)
                    }

                    sectionHeader("LIBRARY")
                    ForEach(Self.libraryRows(showTaps: showTaps)) { libraryRow($0) }

                    sectionHeader("MANAGE")
                    ForEach(Self.manageRows(showAdopt: showAdoptApps)) { libraryRow($0) }

                    sectionHeader("MAINTENANCE")
                    row(.maintenance, title: String(localized: .sidebarHealth), icon: "stethoscope")

                    sectionHeader("CATEGORIES")
                    ForEach(categoryService.orderedCategories, id: \.id) { entry in
                        row(
                            .category(entry.id),
                            title: categoryService.displayName(for: entry.id),
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
        .background {
            if CHType.isNative {
                Color.chNativeSidebar
                    .overlay(alignment: .trailing) { Color.chHairline.frame(width: 1) }
                    .ignoresSafeArea()
            }
        }
        .onChange(of: showAdoptApps) { _, shown in
            if !shown, selection == .library(.adopt) {
                selection = .library(.installed)
            }
        }
        .onChange(of: showTaps) { _, shown in
            if !shown, ContentView.isTapsPage(selection) {
                selection = .library(.installed)
            }
        }
    }

    // MARK: - Rows

    static func libraryRows(showTaps: Bool) -> [SidebarSelection] {
        [.library(.installed), .library(.updates), .library(.saved)] + (showTaps ? [.library(.taps)] : [])
    }

    static func manageRows(showAdopt: Bool) -> [SidebarSelection] {
        [.shelfSetup] + (showAdopt ? [.library(.adopt)] : [])
    }

    @ViewBuilder
    private func libraryRow(_ selection: SidebarSelection) -> some View {
        switch selection {
        case .library(.installed):
            row(selection, title: LibraryItem.installed.title, icon: LibraryItem.installed.icon, count: installedCount)
        case .library(.updates):
            row(selection, title: LibraryItem.updates.title, icon: LibraryItem.updates.icon, badge: updatesCount)
        case .library(.saved):
            row(selection, title: LibraryItem.saved.title, icon: LibraryItem.saved.icon, count: savedCount)
        case .library(.taps):
            row(selection, title: LibraryItem.taps.title, icon: LibraryItem.taps.icon, count: tapsCount)
        case .library(.adopt):
            row(selection, title: LibraryItem.adopt.title, icon: LibraryItem.adopt.icon, count: adoptableCount)
        default:
            row(.shelfSetup, title: String(localized: .sidebarShelfSetup), icon: "books.vertical")
        }
    }

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
                    .font(.system(size: 12 * textScale, weight: .medium))
                    .foregroundStyle(isSelected ? Color.chSelectionFg : Color.chTextMuted)
                    .frame(width: 16 * textScale)
                Text(title)
                    .font(isSelected ? typography.navigationActive : typography.navigation)
                    .foregroundStyle(isSelected ? Color.chSelectionFg : Color.chTextNav)
                    .lineLimit(1)
                    .help(title)
                Spacer(minLength: 4)
                if badge > 0 {
                    CountBadge(count: badge)
                } else if let count, count > 0 {
                    Text("\(count)")
                        .font(typography.status)
                        .foregroundStyle(isSelected ? Color.chSelectionFg : Color.chTextFaint)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.chSelectionBg)
                        .overlay(Capsule().strokeBorder(Color.chHairlineStrong, lineWidth: 1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(typography.label)
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
            service.applyData(CaskCategoryData(
                version: 1,
                generatedDate: "",
                releaseTag: nil,
                categories: [
                    "productivity": CategoryDefinition(displayName: "Productivity", icon: "checklist"),
                    "developerTools": CategoryDefinition(displayName: "Developer Tools", icon: "hammer")
                ],
                tokenToCategory: [:],
                iconTokens: nil
            ))
            return service
        }(),
        updatesCount: 1,
        installedCount: 42,
        tapsCount: 2
    )
    .frame(width: 226, height: 700)
    .background(WindowBackdrop())
}
