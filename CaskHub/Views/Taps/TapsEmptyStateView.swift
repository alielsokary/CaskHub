//
//  TapsEmptyStateView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 11/11/2026.
//

import SwiftUI

struct TapsEmptyStateView: View {
    let onAddTap: () -> Void

    var body: some View {
        VStack(spacing: CHSpace.s3) {
            Image(systemName: LibraryItem.taps.icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.chTextBrand)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.chSurfaceWell))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.chHairline, lineWidth: 1))
            Text("Bring in apps from other taps")
                .font(CHType.section)
                .foregroundStyle(Color.chTextTitle)
            Text("""
                Some developers publish their Mac apps in their own Homebrew repository, called a tap. \
                Add one to browse and install its apps here.
                """)
            .font(CHType.body)
            .foregroundStyle(Color.chTextBody)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
            Button(action: onAddTap) {
                Label("Add Tap", systemImage: "plus")
            }
            .controlSize(.large)
        }
        .padding(CHSpace.s4)
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}
