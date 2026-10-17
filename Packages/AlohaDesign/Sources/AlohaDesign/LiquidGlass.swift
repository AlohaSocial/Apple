// SPDX-License-Identifier: MIT

import SwiftUI

/// Liquid Glass, spelled so that it also compiles on visionOS.
///
/// `glassEffect`, `GlassEffectContainer`, `glassEffectID` and the `.glass`
/// button styles exist on iOS, iPadOS, macOS, tvOS and watchOS, and are
/// unavailable on visionOS — where every window already *is* glass, and the
/// platform's own material is `glassBackgroundEffect`. Calling the system API
/// directly from a view therefore broke the visionOS build of the whole
/// package. These wrappers call exactly that system API everywhere it exists,
/// so nothing changes there, and fall back to visionOS's native material
/// where it does not.

/// A description of a piece of glass: the system's `Glass` where there is
/// one, and enough of it to draw the visionOS equivalent where there is not.
///
/// It reads like `Glass` at the call site — `.regular.tint(…).interactive()`
/// — so moving a view onto it is a rename, not a rewrite.
public nonisolated struct AlohaGlassStyle: Sendable {
    fileprivate var tintColor: Color?
    fileprivate var isInteractive = false

    /// The standard glass.
    public static let regular = AlohaGlassStyle()

    /// Glass tinted with a colour; `nil` leaves it untinted, which is how a
    /// selected/unselected pair shares one expression.
    public func tint(_ color: Color?) -> AlohaGlassStyle {
        var copy = self
        copy.tintColor = color
        return copy
    }

    /// Glass that answers a touch or a pointer.
    public func interactive(_ isEnabled: Bool = true) -> AlohaGlassStyle {
        var copy = self
        copy.isInteractive = isEnabled
        return copy
    }

    #if !os(visionOS)
        /// The system's glass this describes.
        fileprivate var glass: Glass {
            var glass = Glass.regular
            if let tintColor { glass = glass.tint(tintColor) }
            if isInteractive { glass = glass.interactive() }
            return glass
        }
    #endif
}

extension View {
    /// `glassEffect(_:in:)`, or visionOS's own glass background where the
    /// system effect does not exist.
    ///
    /// On visionOS the tint is laid on the glass as a wash, and an interactive
    /// piece lights up when looked at — the platform's equivalent of glass
    /// answering a touch.
    @ViewBuilder
    public func alohaGlassEffect(
        _ style: AlohaGlassStyle = .regular, in shape: some InsettableShape = Capsule()
    ) -> some View {
        #if os(visionOS)
            let base =
                self
                .background {
                    if let tint = style.tintColor { shape.fill(tint.opacity(0.35)) }
                }
                .glassBackgroundEffect(in: shape)
            if style.isInteractive {
                base.contentShape(.hoverEffect, shape).hoverEffect(.highlight)
            } else {
                base
            }
        #else
            glassEffect(style.glass, in: shape)
        #endif
    }

    /// `glassEffectID(_:in:)`, which lets pieces of glass morph into each
    /// other; visionOS has no morphing glass, so there it is nothing.
    @ViewBuilder
    public func alohaGlassEffectID<ID: Hashable & Sendable>(
        _ id: ID?, in namespace: Namespace.ID
    ) -> some View {
        #if os(visionOS)
            self
        #else
            glassEffectID(id, in: namespace)
        #endif
    }

    /// `.buttonStyle(.glass)`, or the bordered style that visionOS draws as
    /// its own glass button.
    @ViewBuilder
    public func alohaGlassButtonStyle() -> some View {
        #if os(visionOS)
            buttonStyle(.bordered)
        #else
            buttonStyle(.glass)
        #endif
    }

    /// `.buttonStyle(.glassProminent)`, or visionOS's prominent bordered
    /// button.
    @ViewBuilder
    public func alohaGlassProminentButtonStyle() -> some View {
        #if os(visionOS)
            buttonStyle(.borderedProminent)
        #else
            buttonStyle(.glassProminent)
        #endif
    }
}

/// `GlassEffectContainer`, which blends nearby glass into one shape and lets
/// it morph; on visionOS, where there is nothing to blend, it is just its
/// content.
public struct AlohaGlassContainer<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        #if os(visionOS)
            content
        #else
            GlassEffectContainer(spacing: spacing) { content }
        #endif
    }
}
