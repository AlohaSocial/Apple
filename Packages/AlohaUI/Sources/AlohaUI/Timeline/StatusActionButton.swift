// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// One of the four actions under a post, with the small celebration that makes
/// tapping it feel like something happened.
///
/// Favouriting is the most repeated gesture in the app and it used to be
/// instant and silent. Here it springs, throws a short burst of sparks in the
/// action's own colour, and taps back through the Taptic Engine.
struct StatusActionButton: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let symbol: String
    let count: Int?
    let tint: Color
    let isOn: Bool
    let style: Style
    let label: Text
    let action: () -> Void

    enum Style {
        /// Scales up and throws sparks. Favourite, bookmark.
        case pop
        /// Turns a full circle. Boost.
        case spin
        /// Nothing beyond the tint. Reply.
        case plain
    }

    @State private var burst = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: AlohaMetrics.space1) {
                ZStack {
                    Image(systemName: symbol)
                        .font(.footnote)
                        // Differentiate Without Colour: the state changes weight
                        // as well as tint (docs/12 §3).
                        .fontWeight(isOn ? .bold : .regular)
                        .symbolVariant(isOn ? .fill : .none)
                        .scaleEffect(scale)
                        .rotationEffect(rotation)

                    if style == .pop, !reduceMotion {
                        SparkBurst(trigger: burst, tint: tint)
                    }
                }
                .frame(width: 18, height: 18)

                if let count, count > 0 {
                    Text(count, format: .number.notation(.compactName))
                        .font(.caption.monospacedDigit().weight(.medium))
                        // Rounded digits read as friendlier and stop the row
                        // jittering as counts change width. A thin numeral at
                        // caption size is the app's smallest text, so it takes
                        // the label colour rather than the secondary one.
                        .fontDesign(.rounded)
                        .foregroundStyle(isOn ? tint : palette.label.opacity(0.75))
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(isOn ? tint : palette.secondaryLabel)
            .frame(minWidth: 52, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .sensoryFeedback(.impact(weight: .light), trigger: isOn) { _, new in new }
        .onChange(of: isOn) { _, new in
            guard new, style == .pop else { return }
            burst += 1
        }
    }

    private var scale: Double {
        guard !reduceMotion, style == .pop else { return 1 }
        return isOn ? 1.15 : 1
    }

    private var rotation: Angle {
        guard !reduceMotion, style == .spin else { return .zero }
        return .degrees(isOn ? 360 : 0)
    }
}

/// A number the row reports but nobody can change: the same shape as an action
/// button, without the button.
///
/// Drawn rather than rendered as a disabled button, because a disabled control
/// says "not now" and this is "not ever, from here" — the server publishes the
/// count and serves no route to add to it.
struct StatusMetric: View {
    @Environment(\.alohaPalette) private var palette

    let symbol: String
    let count: Int
    let label: Text

    var body: some View {
        HStack(spacing: AlohaMetrics.space1) {
            Image(systemName: symbol)
                .font(.footnote)
                .frame(width: 18, height: 18)
            Text(count, format: .number.notation(.compactName))
                .font(.caption.monospacedDigit().weight(.medium))
                .fontDesign(.rounded)
                .contentTransition(.numericText())
        }
        .foregroundStyle(palette.tertiaryLabel)
        .frame(minWidth: 52, minHeight: 32, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// A handful of sparks thrown outward once, then gone.
private struct SparkBurst: View {
    let trigger: Int
    let tint: Color

    private static let count = 8

    var body: some View {
        ZStack {
            ForEach(0..<Self.count, id: \.self) { index in
                Circle()
                    .fill(tint)
                    .frame(width: 3, height: 3)
                    .modifier(
                        SparkFlight(
                            angle: .degrees(Double(index) / Double(Self.count) * 360),
                            progress: trigger == 0 ? 0 : 1))
            }
        }
        .animation(.easeOut(duration: 0.45), value: trigger)
        .allowsHitTesting(false)
    }
}

/// Animating one value keeps the whole burst on a single spring rather than
/// eight competing ones.
private struct SparkFlight: ViewModifier, @preconcurrency Animatable {
    let angle: Angle
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        // Out and gone: a spark that lingers reads as a rendering bug.
        let distance = 14 * eased
        return
            content
            .offset(x: cos(angle.radians) * distance, y: sin(angle.radians) * distance)
            .opacity(fade)
            .scaleEffect(1 - eased * 0.4)
    }

    /// The flight is one-shot: `progress` goes 0 → 1 and stays there, so the
    /// sparks must fade out on their own within that single pass.
    private var eased: Double {
        let cycled = progress.truncatingRemainder(dividingBy: 1)
        return cycled == 0 && progress > 0 ? 1 : cycled
    }

    private var fade: Double {
        guard progress > 0 else { return 0 }
        return max(0, 1 - eased * 1.6)
    }
}
