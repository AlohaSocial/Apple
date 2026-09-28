// SPDX-License-Identifier: MIT

import SwiftUI

/// A filled button whose contrast does not depend on what is behind it.
///
/// `.borderedProminent` draws its fill as translucent material, so white text
/// on the accent measures differently over cream, over a photograph, and over
/// a scrolling timeline — Apple's accessibility audit fails it on all three.
/// This paints the accent itself and takes the theme's matching text colour.
public struct AlohaProminentButtonStyle: ButtonStyle {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(palette.onAccent)
            .padding(.vertical, AlohaMetrics.space3)
            .padding(.horizontal, AlohaMetrics.space4)
            .frame(minHeight: 44)
            .background(palette.accent.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AlohaProminentButtonStyle {
    public static var alohaProminent: AlohaProminentButtonStyle { AlohaProminentButtonStyle() }
}
