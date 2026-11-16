// SPDX-License-Identifier: MIT

import SwiftUI

/// The small celebration thrown off an action as it turns on: a ring and a
/// handful of hearts for a favourite, sparks for a bookmark.
///
/// Mounted only while it plays. The burst it replaced sat in every
/// favourite and bookmark button of every row for good — sixteen invisible
/// views a row, laid out and diffed on every frame of a scroll — to be seen
/// for half a second after a tap. Now a row carries nothing until it is
/// tapped, and the burst takes itself away when it is done.
///
/// Reduce Motion never gets here: the button only mounts a burst when
/// motion is allowed, and otherwise the state change — the outline filling
/// and the tint — is the whole answer, as docs/12 §3 asks.
struct CelebrationBurst: View {
    enum Kind {
        /// A ring and hearts, in the favourite's colour.
        case hearts
        /// Sparks, in the action's colour.
        case sparks
    }

    let kind: Kind
    let tint: Color
    /// Called once the burst has played, so the button can unmount it.
    let onFinished: () -> Void

    @State private var progress = 0.0

    /// About as long as the system's own bounce, so the glyph and its burst
    /// land together; and as long as the Senses tick takes to fade.
    static let duration = 0.5

    var body: some View {
        ZStack {
            if kind == .hearts {
                Circle()
                    .strokeBorder(tint, lineWidth: 1.5)
                    .modifier(RingPulse(progress: progress))
            }
            ForEach(Self.particles(for: kind), id: \.self) { angle in
                particle
                    .modifier(ParticleFlight(angle: angle, reach: reach, progress: progress))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: Self.duration)) {
                progress = 1
            } completion: {
                onFinished()
            }
        }
    }

    @ViewBuilder
    private var particle: some View {
        switch kind {
        case .hearts:
            Image(systemName: "heart.fill")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(tint)
        case .sparks:
            Circle()
                .fill(tint)
                .frame(width: 3, height: 3)
        }
    }

    private var reach: Double { kind == .hearts ? 17 : 14 }

    /// Where each particle flies, in degrees clockwise from the top.
    ///
    /// Hearts go up and out in a fan — a heart thrown downwards reads as one
    /// falling — and sparks all the way round, as they always have.
    static func particles(for kind: Kind) -> [Double] {
        switch kind {
        case .hearts: [-70, -40, -12, 12, 40, 70]
        case .sparks: stride(from: 0.0, to: 360, by: 45).map { $0 }
        }
    }
}

/// One value drives every particle, so the burst runs on a single animation
/// rather than one per particle.
private struct ParticleFlight: ViewModifier, @preconcurrency Animatable {
    let angle: Double
    let reach: Double
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let radians = (angle - 90) * .pi / 180
        let distance = reach * progress
        return
            content
            .offset(x: cos(radians) * distance, y: sin(radians) * distance)
            .scaleEffect(0.5 + 0.7 * sin(progress * .pi))
            // Out and gone: a particle that lingers reads as a rendering bug.
            .opacity(progress < 0.35 ? 1 : max(0, 1 - (progress - 0.35) / 0.65))
    }
}

/// The ring a favourite throws: it grows from the glyph and thins away.
private struct RingPulse: ViewModifier, @preconcurrency Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.6 + 1.1 * progress)
            .opacity(max(0, 0.7 * (1 - progress)))
    }
}
