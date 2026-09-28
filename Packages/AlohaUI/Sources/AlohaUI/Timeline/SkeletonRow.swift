// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// The shape of a post, shimmering, while the first page is on its way.
///
/// A cold launch used to show an empty screen, which reads as "broken" rather
/// than "working". Three of these read as the app doing something.
struct SkeletonRow: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let hasMedia: Bool

    @State private var phase: Double = -1

    var body: some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            Circle()
                .fill(fill)
                .frame(width: metrics.avatarSize, height: metrics.avatarSize)

            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                bar(width: 140, height: 12)
                bar(width: nil, height: 10)
                bar(width: 220, height: 10)
                if hasMedia {
                    RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                        .fill(fill)
                        .frame(height: 160)
                        .padding(.top, AlohaMetrics.space2)
                }
            }
        }
        .padding(.vertical, metrics.density.rowPadding)
        .task {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 2
            }
        }
        .accessibilityHidden(true)
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
