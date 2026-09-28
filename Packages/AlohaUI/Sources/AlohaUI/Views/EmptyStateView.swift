// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// What a screen shows when it has nothing to show.
///
/// A grey glyph and a flat sentence read as a dead end. A tinted, layered
/// symbol and — where there is something useful to do — a button, read as an
/// invitation.
public struct EmptyStateView<Action: View>: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let symbol: String
    private let title: Text
    private let message: Text?
    private let action: Action

    @State private var hasAppeared = false

    public init(
        symbol: String, title: Text, message: Text? = nil,
        @ViewBuilder action: () -> Action = { EmptyView() }
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.action = action()
    }

    public var body: some View {
        VStack(spacing: AlohaMetrics.space4) {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.10))
                    .frame(width: 96, height: 96)
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .regular))
                    .foregroundStyle(palette.accent)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.7)
            .opacity(hasAppeared || reduceMotion ? 1 : 0)

            VStack(spacing: AlohaMetrics.space2) {
                title
                    .font(.headline)
                    .foregroundStyle(palette.label)
                if let message {
                    message
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                        .multilineTextAlignment(.center)
                }
            }

            action
                .buttonStyle(.alohaProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AlohaMetrics.space6)
        .padding(.horizontal, AlohaMetrics.space4)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { hasAppeared = true }
        }
    }
}
