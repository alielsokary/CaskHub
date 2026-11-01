//
//  RetirementBadge.swift
//  CaskHub
//
//  Created by Ali Elsokary on 01/11/2026.
//

import SwiftUI

struct RetirementBadge: View {
    let retirement: CaskRetirement
    let isInstalled: Bool

    var body: some View {
        let summary = retirement.summary(isInstalled: isInstalled)
        Image(systemName: "exclamationmark.shield.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(retirement.blocksInstall ? Color.red : Color.yellow)
            .contentShape(Rectangle())
            .help(summary)
            .accessibilityLabel(retirement.blocksInstall ? String(localized: "Disabled") : String(localized: "Deprecated"))
            .accessibilityHint(summary)
    }
}
