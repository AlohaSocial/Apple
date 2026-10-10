// SPDX-License-Identifier: MIT

import SwiftUI

/// The shape of a list arriving, in the one place every list can share.
///
/// Each screen had grown its own spinner-over-blank, or nothing at all —
/// half the lists in the app opened as an empty screen with a spinner, and
/// the other half opened as nothing. A list in progress should look like the
/// list it is about to be (docs/05 §4).
public struct SkeletonListRow: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Kind {
        /// Avatar plus two lines: a person, a conversation, a thread.
        case person
        /// Two lines only: a title and a detail.
        case text
        /// A block: a card, a tile.
        case block
    }

    private let kind: Kind
    private let count: Int

    @State private var phase: Double = -1

    public init(person count: Int = 6) {
        self.kind = .person
        self.count = max(1, count)
    }

    public init(text count: Int = 3) {
        self.kind = .text
        self.count = max(1, count)
    }

    public init(block count: Int = 2) {
        self.kind = .block
        self.count = max(1, count)
    }

    public var body: some View {
        Section {
            ForEach(0..<count, id: \.self) { _ in
                row
            }
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 2
            }
        }
    }

    @ViewBuilder
    private var row: some View {
        switch kind {
        case .person:
            HStack(spacing: AlohaMetrics.space3) {
                Circle()
                    .fill(fill)
                    .frame(width: metrics.avatarSize, height: metrics.avatarSize)
                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    bar(width: 160, height: 12)
                    bar(width: 100, height: 10)
                }
            }
            .padding(.vertical, AlohaMetrics.space2)
            .padding(.horizontal, AlohaMetrics.space3)

        case .text:
            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                bar(width: 140, height: 12)
                bar(width: nil, height: 10)
            }
            .padding(.vertical, AlohaMetrics.space2)
            .padding(.horizontal, AlohaMetrics.space3)

        case .block:
            RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                .fill(fill)
                .frame(height: 132)
                .padding(.vertical, AlohaMetrics.space2)
                .padding(.horizontal, AlohaMetrics.space3)
        }
    }

    private func bar(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    /// The sweep is a gradient moved across the shape rather than an opacity
    /// pulse: it reads as light travelling, not as flicker.
    private var fill: some ShapeStyle {
        LinearGradient(
            stops: [
                .init(color: palette.surfaceRaised, location: 0),
                .init(color: palette.separator.opacity(0.55), location: 0.5),
                .init(color: palette.surfaceRaised, location: 1),
            ],
            startPoint: UnitPoint(x: phase, y: 0.5),
            endPoint: UnitPoint(x: phase + 1, y: 0.5))
    }
}

#Preview {
    List {
        SkeletonListRow(person: 4)
    }
}
