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

    /// Where the button sits. A timeline row packs five controls and their
    /// numbers into the width next to an avatar, so they are small and read
    /// left-aligned. An opened post has the whole width for the same five, so
    /// they are evenly spread, centred and drawn at the size of a tap target.
    var prominence: Prominence = .row

    /// When set, the number becomes its own control: the glyph performs the
    /// action and the number opens what stands behind it — who favourited,
    /// who boosted — the way X and Threads do it. A control that is not
    /// offered stays part of the glyph's button, as it is in the timeline.
    var onCountTap: (() -> Void)? = nil

    /// What VoiceOver says about the number when it is its own control.
    var countHint: Text? = nil

    /// How the glyph and its number sit in their cell. A strip spreads equal
    /// cells and centres what each holds; a row on its own reads from the
    /// leading edge.
    var contentAlignment: Alignment? = nil

    let action: () -> Void

    enum Style {
        /// Bounces and throws sparks. Favourite, bookmark.
        case pop
        /// Turns. Boost.
        case spin
        /// Nothing beyond the tint. Reply.
        case plain
    }

    enum Prominence {
        case row
        case detail
    }

    /// Counted rather than toggled, so only turning an action *on* moves
    /// the glyph — undoing a favourite is not a celebration.
    @State private var burst = 0
    @State private var spin = 0

    private var minimumHeight: Double { prominence == .row ? 32 : 44 }
    private var iconSide: Double { prominence == .row ? 18 : 24 }

    var body: some View {
        Group {
            if let onCountTap, let count, count > 0 {
                // Two controls side by side: the glyph acts, the number tells
                // and opens. Not a button inside a button, which SwiftUI
                // resolves as one control and swallows the inner one.
                HStack(spacing: AlohaMetrics.space1) {
                    Button(action: action) {
                        glyph
                            .frame(minWidth: iconSide + 6, minHeight: minimumHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label)

                    Button(action: onCountTap) {
                        countText(count)
                            .frame(minHeight: minimumHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(label) \(Text(count, format: .number))"))
                    .accessibilityHint(countHint ?? Text(verbatim: ""))
                }
            } else {
                Button(action: action) {
                    HStack(spacing: AlohaMetrics.space1) {
                        glyph
                        if let count, count > 0 { countText(count) }
                    }
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .modifier(CountAccessibilityValue(count: count))
            }
        }
        .frame(
            minWidth: 44,
            maxWidth: prominence == .row ? nil : .infinity,
            minHeight: minimumHeight,
            alignment: alignment
        )
        .foregroundStyle(isOn ? tint : palette.secondaryLabel)
        .contentShape(Rectangle())
        .alohaHoverTarget(prominence == .row ? AnyShape(Capsule()) : AnyShape(Circle()))
        .alohaLargeContentViewer(symbol: symbol, label: label)
        .onChange(of: isOn) { _, new in
            guard new else { return }
            switch style {
            case .pop: burst += 1
            case .spin: spin += 1
            case .plain: break
            }
        }
    }

    private var alignment: Alignment {
        contentAlignment ?? (prominence == .row ? .leading : .center)
    }

    /// The glyph and its celebration, without the number.
    private var glyph: some View {
        ZStack {
            Image(systemName: symbol)
                .font(prominence == .row ? .footnote : .body)
                // Differentiate Without Colour: the state changes weight
                // as well as tint (docs/12 §3).
                .fontWeight(isOn ? .bold : .regular)
                .symbolVariant(isOn ? .fill : .none)
                // SF Symbols' own motion rather than a hand-made scale
                // and spin: the outline-to-fill change is the symbol's
                // replace transition, and turning an action on bounces
                // or turns the glyph the way the system's own do.
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.up, options: .nonRepeating, value: burst)
                .symbolEffect(.rotate.clockwise, options: .nonRepeating, value: spin)
                .symbolEffectsRemoved(reduceMotion)

            if style == .pop, !reduceMotion {
                SparkBurst(trigger: burst, tint: tint)
            }
        }
        .frame(width: iconSide, height: iconSide)
    }

    private func countText(_ count: Int) -> some View {
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

/// A number drawn inside a button is still worth hearing: it is what the
/// action has amounted to so far.
private struct CountAccessibilityValue: ViewModifier {
    let count: Int?

    func body(content: Content) -> some View {
        if let count, count > 0 {
            content.accessibilityValue(Text(count, format: .number))
        } else {
            content
        }
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
        .frame(minWidth: 44, minHeight: 32, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .alohaLargeContentViewer(symbol: symbol, label: label)
    }
}

extension View {
    /// The Large Content Viewer: at the accessibility text sizes, a long press
    /// on a small fixed-size control shows it large in the middle of the
    /// screen. The action row's glyphs do not grow with text — that is what
    /// keeps the row on one line — so this is how they stay readable.
    func alohaLargeContentViewer(symbol: String, label: Text) -> some View {
        #if os(iOS) || os(visionOS)
            accessibilityShowsLargeContentViewer {
                Label {
                    label
                } icon: {
                    Image(systemName: symbol)
                }
            }
        #else
            self
        #endif
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
