//
//  CatalogScrollSupport.swift
//  CaskHub
//
//  Created by Ali Elsokary on 03/08/2026.
//

import SwiftUI

/// Last item of a lazy container: materializing means the user hit the cap.
struct RevealSentinel: View {
    let onReveal: () -> Void

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onAppear(perform: onReveal)
    }
}

struct ResetScrollOnChange<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    @State private var position = ScrollPosition(edge: .top)
    @State private var isAtTop = true

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y <= geometry.contentInsets.top + 1
            } action: { _, newValue in
                isAtTop = newValue
            }
            .onChange(of: trigger) {
                guard !isAtTop else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    position.scrollTo(edge: .top)
                }
            }
    }
}
