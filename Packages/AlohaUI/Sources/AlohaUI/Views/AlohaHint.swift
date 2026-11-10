// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// A short explanation the reader can accept or put away for good.
///
/// TipKit teaches a gesture once, in a popover that covers the thing it is
/// about and cannot be dismissed by the gesture people reach for first —
/// swiping it away. These are inline instead: a quiet card in the flow, a
/// close button, and a swipe in either direction that means the same thing.
/// What is put away stays away, per hint, so nobody is told twice.
struct AlohaHint: View {
    @Environment(\.alohaPalette) private var palette

    let id: String
    let symbol: String
    let title: Text
    let message: Text
    var actionTitle: Text?
    var action: (() -> Void)?

    @AppStorage private var isDismissed: Bool

    init(
        id: String, symbol: String, title: Text, message: Text,
        actionTitle: Text? = nil, action: (() -> Void)? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        _isDismissed = AppStorage(wrappedValue: false, "aloha.hint.\(id)")
    }

    var body: some View {
        if !isDismissed {
            HStack(alignment: .top, spacing: AlohaMetrics.space3) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(palette.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.label)
                    message
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)

                    if let actionTitle, let action {
                        Button(action: action) {
                            actionTitle
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(palette.accent)
                                .padding(.top, 2)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.tertiaryLabel)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss hint", comment: "Hint action"))
            }
            .padding(AlohaMetrics.space3)
            .background(
                palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                    .strokeBorder(palette.separator.opacity(0.6), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 16).onEnded { value in
                    if abs(value.translation.width) > 60 { dismiss() }
                }
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.22)) { isDismissed = true }
    }
}
