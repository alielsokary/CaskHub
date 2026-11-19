//
//  SavedEmptyStateView.swift
//  CaskHub
//
//  Created by therustyrobot on 19/11/2026.
//

import SwiftUI

struct SavedEmptyStateView: View {
    var body: some View {
        VStack(spacing: CHSpace.s3) {
            Image(systemName: LibraryItem.saved.icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.chTextBrand)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.chSurfaceWell))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.chHairline, lineWidth: 1))
            Text("Nothing saved yet")
                .font(CHType.section)
                .foregroundStyle(Color.chTextTitle)
            Text("Tap the bookmark on any app to keep it here for later.")
                .font(CHType.body)
                .foregroundStyle(Color.chTextBody)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding(CHSpace.s4)
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}
