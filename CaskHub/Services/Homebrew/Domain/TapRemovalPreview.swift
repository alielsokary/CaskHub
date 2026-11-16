//
//  TapRemovalPreview.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import Foundation

/// What `brew untap` will uninstall along with the tap.
nonisolated struct TapRemovalPreview: Equatable, Sendable {
    let tapName: String
    let installedCasks: [Cask]
    let installedFormulae: [String]

    var removesInstalledItems: Bool {
        !installedCasks.isEmpty || !installedFormulae.isEmpty
    }
}
