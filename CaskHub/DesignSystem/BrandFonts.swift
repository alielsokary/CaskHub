//
//  BrandFonts.swift
//  CaskHub
//
//  Created by Ali Elsokary on 07/07/2026.
//

import CoreText
import Foundation

// Registers the bundled brand fonts (Baloo 2, Nunito, JetBrains Mono — all SIL OFL)
// for this process. Called once from CaskHubApp.init.
enum BrandFonts {
    static func register() {
        for name in ["Baloo2", "Nunito", "JetBrainsMono"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
