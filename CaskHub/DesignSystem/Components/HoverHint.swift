//
//  HoverHint.swift
//  CaskHub
//
//  Created by Ali Elsokary on 15/11/2026.
//

import SwiftUI

extension View {
    /// Explains state in a popover the moment the pointer enters. A nil message shows nothing.
    /// Not for enabled controls: the transient popover swallows the next click to dismiss itself.
    func hoverHint(_ message: String?) -> some View {
        modifier(HoverHint(message: message))
    }
}

private struct HoverHint: ViewModifier {
    let message: String?

    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onHover { isPresented = $0 && message != nil }
            .popover(isPresented: $isPresented) {
                HintWidth(maxWidth: 260) {
                    Text(verbatim: message ?? "")
                        .font(CHType.bodySm)
                }
                .padding(12)
            }
            .accessibilityHint(message.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
    }
}

/// Popovers size content with an unspecified proposal, which leaves long text on one clipped line.
struct HintWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let width = min(text.sizeThatFits(.unspecified).width, maxWidth)
        return text.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
