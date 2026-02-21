//
//  CaskIconView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import SwiftUI

struct CaskIconView: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(.quaternary)
                .frame(width: size, height: size)
            Image(systemName: "macwindow")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        CaskIconView(size: 32)
        CaskIconView(size: 44)
        CaskIconView(size: 56)
    }
    .padding()
}
