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

    @AppStorage("catalogTextSize") private var catalogTextSize: CatalogTextSize = .standard

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
        .onChange(of: selectedTheme) { _, newValue in
            Analytics.themeChanged(newValue)
        }
    }

    private let textSizeLabels: [LocalizedStringKey] = ["Standard", "Larger (110%)", "Largest (120%)"]

    private var textSizeStep: Binding<Double> {
        Binding(
            get: { Double(CatalogTextSize.allCases.firstIndex(of: catalogTextSize) ?? 0) },
            set: { catalogTextSize = CatalogTextSize.allCases[Int(min(2, max(0, $0.rounded())))] }
        )
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
