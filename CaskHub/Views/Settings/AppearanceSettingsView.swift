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
                        selectionCard(for: option)
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

    private func selectionCard(for option: AppTheme) -> some View {
        let isSelected = selectedTheme == option.rawValue
        return Button { selectedTheme = option.rawValue } label: {
            VStack(spacing: 6) {
                Image(nsImage: option.previewImage ?? NSImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 67)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    )
                Text(option.title)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(option.title) theme"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    AppearanceSettingsView()
}
