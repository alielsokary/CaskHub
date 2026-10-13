//
//  AppearanceSettingsView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 19/07/2026.
//

import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue
    @AppStorage(AppStyle.storageKey) private var selectedStyle: AppStyle = .classic

    @AppStorage("catalogTextSize") private var catalogTextSize: CatalogTextSize = .standard

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                AppStylePicker(scale: 0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                MatchSystemToggle(showsDetail: true)
            } header: {
                HStack {
                    Text("Theme")
                    Spacer()
                    Text(verbatim: "\(selectedStyle.title) · \(modeSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Text Size") {
                HStack(alignment: .top) {
                    Text("Text size")
                    Spacer(minLength: 16)
                    VStack(spacing: 8) {
                        Slider(value: textSizeStep, in: 0 ... 2, step: 1) {
                            Text("Text size")
                        }
                        .labelsHidden()
                        .accessibilityValue(Text(textSizeLabels[Int(textSizeStep.wrappedValue)]))
                        HStack {
                            Text(textSizeLabels[0])
                            Spacer()
                            Text(textSizeLabels[1])
                            Spacer()
                            Text(textSizeLabels[2])
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    }
                    .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                Text("Adjust text in app cards, lists, the sidebar, and the status bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    static func theme(afterPicking mode: AppTheme, current: AppTheme) -> AppTheme {
        current == .system ? .system : mode
    }

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .system
    }

    private var currentMode: AppTheme {
        colorScheme == .dark ? .dark : .light
    }

    private var modeSummary: String {
        theme == .system
            ? String(localized: "System (Currently \(currentMode.title))")
            : theme.title
    }

    private let textSizeLabels: [LocalizedStringKey] = ["Standard", "Larger (110%)", "Largest (120%)"]

    private var textSizeStep: Binding<Double> {
        Binding(
            get: { Double(CatalogTextSize.allCases.firstIndex(of: catalogTextSize) ?? 0) },
            set: { catalogTextSize = CatalogTextSize.allCases[Int(min(2, max(0, $0.rounded())))] }
        )
    }
}

// MARK: - Match system toggle

struct MatchSystemToggle: View {
    let showsDetail: Bool

    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Toggle(isOn: matchesSystem) {
            Text("Match system appearance")
            if showsDetail {
                Text("Switch between the light and dark halves with macOS")
            }
        }
        .toggleStyle(.switch)
    }

    private var matchesSystem: Binding<Bool> {
        Binding(
            get: { selectedTheme == AppTheme.system.rawValue },
            set: { selectedTheme = ($0 ? AppTheme.system : colorScheme == .dark ? .dark : .light).rawValue }
        )
    }
}

// MARK: - Style picker

struct AppStylePicker: View {
    let scale: CGFloat

    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue
    @AppStorage(AppStyle.storageKey) private var selectedStyle: AppStyle = .classic

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(AppStyle.allCases) { style in
                ThemeSplitCard(
                    style: style,
                    isSelected: style == selectedStyle,
                    theme: theme,
                    scale: scale
                ) { mode in
                    selectedStyle = style
                    selectedTheme = AppearanceSettingsView.theme(afterPicking: mode, current: theme).rawValue
                }
            }
        }
        .onChange(of: selectedTheme) { _, newValue in
            Analytics.themeChanged(newValue)
        }
        .onChange(of: selectedStyle) { _, newValue in
            Analytics.styleChanged(newValue)
        }
    }

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .system
    }
}

// MARK: - Split card

private struct ThemeSplitCard: View {
    let style: AppStyle
    let isSelected: Bool
    let theme: AppTheme
    let scale: CGFloat
    let onPick: (AppTheme) -> Void

    private static let accent = Color(hex: 0xC8674A)

    var body: some View {
        VStack(spacing: 8) {
            preview
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { ring }
                .overlay {
                    HStack(spacing: 0) {
                        half(.light)
                        half(.dark)
                    }
                }
            if theme != .system {
                HStack(spacing: 0) {
                    modeLabel(.light)
                    modeLabel(.dark)
                }
                .font(.system(size: 11, weight: .medium))
            }
            Text(style.title)
                .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(width: ThemeMiniWindow.size.width * scale)
    }

    private var preview: some View {
        ZStack {
            ThemeMiniWindow(palette: .of(style, dark: false))
            ThemeMiniWindow(palette: .of(style, dark: true))
                .mask(alignment: .trailing) {
                    Rectangle().frame(width: ThemeMiniWindow.size.width / 2)
                }
        }
        .scaleEffect(scale)
        .frame(width: ThemeMiniWindow.size.width * scale, height: ThemeMiniWindow.size.height * scale)
    }

    @ViewBuilder
    private var ring: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if isSelected, theme == .system {
            shape.strokeBorder(Self.accent, lineWidth: 3)
        } else if !isSelected {
            shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private func isHighlighted(_ mode: AppTheme) -> Bool {
        isSelected && theme == mode
    }

    private func half(_ mode: AppTheme) -> some View {
        Button {
            onPick(mode)
        } label: {
            Color.clear
                .contentShape(Rectangle())
                .overlay {
                    if isSelected, theme == mode {
                        UnevenRoundedRectangle(
                            topLeadingRadius: mode == .light ? 10 : 0,
                            bottomLeadingRadius: mode == .light ? 10 : 0,
                            bottomTrailingRadius: mode == .dark ? 10 : 0,
                            topTrailingRadius: mode == .dark ? 10 : 0,
                            style: .continuous
                        )
                        .strokeBorder(Self.accent, lineWidth: 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: theme == .system ? style.title : "\(style.title), \(mode.title)"))
        .accessibilityAddTraits(isSelected && theme == mode ? .isSelected : [])
    }

    private func modeLabel(_ mode: AppTheme) -> some View {
        Text(mode.title)
            .foregroundStyle(isHighlighted(mode) ? AnyShapeStyle(Self.accent) : AnyShapeStyle(.tertiary))
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Mini window

private struct ThemeMiniWindow: View {
    static let size = CGSize(width: 300, height: 190)
    private static let lineWidths: [CGFloat] = [44, 52, 38, 48]
    private static let trafficLights: [UInt32] = [0xFF5F57, 0xFEBC2E, 0x28C840]

    let palette: ThemePreviewPalette

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 82)
            content
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background {
            if let dots = palette.dots {
                HalftoneTexture(color: dots, step: 6, dot: 1)
            }
        }
        .background(palette.background)
    }

    private var sidebar: some View {
        let shape = RoundedRectangle(cornerRadius: palette.sidebarRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 3) {
                ForEach(Self.trafficLights, id: \.self) { Circle().fill(Color(hex: $0)).frame(width: 5, height: 5) }
            }
            Capsule().fill(palette.selection).frame(width: 56, height: 9).padding(.top, 4)
            ForEach(Self.lineWidths, id: \.self) { width in
                RoundedRectangle(cornerRadius: 3).fill(palette.line).frame(width: width, height: 5)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(palette.sidebar).shadow(color: palette.sidebarShadow, radius: 2, y: 1))
        .overlay(alignment: .trailing) { palette.sidebarEdge.frame(width: 1) }
        .padding(palette.sidebarInset)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule().fill(palette.bar).frame(width: 110, height: 12)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow { card(palette.pills[0]); card(palette.pills[1]) }
                GridRow { card(palette.pills[2]); card(palette.pills[3]) }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 8, bottom: 0, trailing: 12))
    }

    private func card(_ pill: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(palette.terminal).frame(width: 12, height: 12)
                RoundedRectangle(cornerRadius: 3).fill(palette.line).frame(width: 44, height: 5)
            }
            RoundedRectangle(cornerRadius: 3).fill(palette.line).frame(width: 57, height: 4)
            Spacer(minLength: 0)
            Capsule().fill(pill).frame(height: 10)
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .topLeading)
        .background(shape.fill(palette.card).shadow(color: palette.cardShadow, radius: 3, y: 2))
        .overlay { shape.strokeBorder(palette.cardEdge, lineWidth: 1) }
    }
}

/// Fixed design colours, independent of the live theme.
private struct ThemePreviewPalette {
    var background: Color
    var dots: Color?
    var sidebar: Color
    var sidebarInset: CGFloat = 0
    var sidebarRadius: CGFloat = 0
    var sidebarEdge: Color = .clear
    var sidebarShadow: Color = .clear
    var selection: Color
    var line: Color
    var bar: Color
    var card: Color
    var cardEdge: Color = .clear
    var cardShadow: Color = .clear
    var terminal: Color
    var pills: [Color]

    static func of(_ style: AppStyle, dark: Bool) -> ThemePreviewPalette {
        switch (style, dark) {
        case (.classic, false):
            ThemePreviewPalette(
                background: Color(hex: 0xF6E9CB), dots: Color(hex: 0x33304A, alpha: 0.09), sidebar: Color(hex: 0xFDF6E4),
                sidebarEdge: .white.opacity(0.7), selection: Color(hex: 0xC8674A, alpha: 0.38),
                line: Color(hex: 0x33304A, alpha: 0.18), bar: Color(hex: 0xFDF6E4, alpha: 0.95),
                card: Color(hex: 0xFDF6E4, alpha: 0.92), cardEdge: .white.opacity(0.85),
                cardShadow: Color(hex: 0x33304A, alpha: 0.1), terminal: Color(hex: 0x33304A),
                pills: [Color(hex: 0x6FA287, alpha: 0.4), Color(hex: 0xD99A4E, alpha: 0.45),
                        Color(hex: 0xC8674A, alpha: 0.36), Color(hex: 0xC8674A, alpha: 0.36)]
            )
        case (.classic, true):
            ThemePreviewPalette(
                background: Color(hex: 0x2B2838), dots: Color(hex: 0xF6E9CB, alpha: 0.07), sidebar: Color(hex: 0x252232),
                sidebarEdge: .white.opacity(0.08), selection: Color(hex: 0xC8674A, alpha: 0.45),
                line: Color(hex: 0xF6E9CB, alpha: 0.2), bar: Color(hex: 0x353147, alpha: 0.95),
                card: Color(hex: 0x353147), cardEdge: .white.opacity(0.12), terminal: Color(hex: 0x211E2C),
                pills: [Color(hex: 0x6FA287, alpha: 0.4), Color(hex: 0xD99A4E, alpha: 0.42),
                        Color(hex: 0xC8674A, alpha: 0.42), Color(hex: 0xC8674A, alpha: 0.42)]
            )
        case (.native, false):
            ThemePreviewPalette(
                background: Color(hex: 0xF7F7F8), sidebar: Color(hex: 0xEFEEF0), sidebarInset: 4, sidebarRadius: 8,
                sidebarShadow: .black.opacity(0.08), selection: Color(hex: 0xC8674A, alpha: 0.2),
                line: .black.opacity(0.12), bar: .black.opacity(0.06), card: .white,
                cardShadow: .black.opacity(0.06), terminal: Color(hex: 0x33304A),
                pills: [Color(hex: 0xD9EBDF), Color(hex: 0xF8E6C8), Color(hex: 0xF6DDD3), Color(hex: 0xF6DDD3)]
            )
        case (.native, true):
            ThemePreviewPalette(
                background: Color(hex: 0x1F1E22), sidebar: Color(hex: 0x27262B), sidebarInset: 4, sidebarRadius: 8,
                sidebarShadow: .black.opacity(0.3), selection: Color(hex: 0xE8916F, alpha: 0.28),
                line: .white.opacity(0.14), bar: .white.opacity(0.07), card: Color(hex: 0x2C2B30),
                cardShadow: .black.opacity(0.14), terminal: Color(hex: 0x3A393F),
                pills: [Color(hex: 0x689E80, alpha: 0.32), Color(hex: 0xC88C42, alpha: 0.32),
                        Color(hex: 0xC46246, alpha: 0.36), Color(hex: 0xC46246, alpha: 0.36)]
            )
        }
    }
}

#Preview {
    AppearanceSettingsView()
        .frame(width: 650, height: 560)
}
