// SPDX-License-Identifier: MIT

import SwiftUI

/// The selected state of a navigation row, in the system's own material.
///
/// A selected sidebar row in Apple's apps is Liquid Glass: a lit capsule of
/// material behind the row, tinted with the accent, that lets the sidebar's
/// own background show through its edges. An accent-coloured wash behind a row
/// is the approximation — it reads as a highlight, not as a layer, and it
/// ignores whatever is scrolled behind it.
///
/// Falls back to the tinted capsule on systems without the material, so a row
/// never loses its selected state for the sake of a blur.
public struct SelectedGlass: ViewModifier {
    private let isSelected: Bool
    private let tint: Color

    public init(_ isSelected: Bool, tint: Color) {
        self.isSelected = isSelected
        self.tint = tint
    }

    public func body(content: Content) -> some View {
        if isSelected {
            content
                #if os(iOS) || os(macOS) || os(visionOS)
                    .glassEffect(
                        .regular.tint(tint.opacity(0.22)).interactive(),
                        in: Capsule())
                #else
                    .background(
                        tint.opacity(0.16),
                        in: Capsule())
                #endif
        } else {
            content
        }
    }
}

extension View {
    /// The selected state of a navigation row: Liquid Glass when selected,
    /// nothing at all when not.
    public func selectedGlass(_ isSelected: Bool, tint: Color) -> some View {
        modifier(SelectedGlass(isSelected, tint: tint))
    }
}

#Preview {
    VStack(spacing: 8) {
        Text("Selected").padding().selectedGlass(true, tint: .accentColor)
        Text("Not selected").padding().selectedGlass(false, tint: .accentColor)
    }
    .padding()
}
