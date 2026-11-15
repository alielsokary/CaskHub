//
//  ShelfSetupPresentation.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/11/2026.
//

import SwiftUI

enum ShelfSetupPicker: String, Identifiable {
    case adoptIgnore
    case pin

    var id: String { rawValue }
}

/// Presented from the split view, not the detail column, so the sheet centers on the whole window.
struct ShelfSetupPresentation: ViewModifier {
    @Binding var picker: ShelfSetupPicker?
    let viewModel: CaskCatalogViewModel

    func body(content: Content) -> some View {
        content.sheet(item: $picker) { picker in
            switch picker {
            case .adoptIgnore: AdoptIgnorePickerSheet(viewModel: viewModel)
            case .pin: PinPickerSheet(viewModel: viewModel)
            }
        }
    }
}
