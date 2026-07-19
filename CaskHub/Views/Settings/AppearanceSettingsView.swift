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

    var body: some View {
        Form {
            Section("App Theme") {
                HStack(spacing: 16) {
                    ForEach(AppTheme.allCases) { option in
                        selectionCard(
                            image: option.previewImage,
                            size: CGSize(width: 104, height: 67),
                            title: option.rawValue,
                            accessibilityLabel: "\(option.rawValue) theme",
                            isSelected: selectedTheme == option.rawValue
                        ) { selectedTheme = option.rawValue }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: selectedTheme) { _, newValue in
            Analytics.themeChanged(newValue)
        }
    }

    private func selectionCard(
        image: NSImage?,
        size: CGSize,
        title: String,
        accessibilityLabel: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(nsImage: image ?? NSImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    )
                Text(title)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    AppearanceSettingsView()
}
