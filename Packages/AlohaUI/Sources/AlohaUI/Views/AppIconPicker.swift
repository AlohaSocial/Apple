// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

#if os(iOS)
    import UIKit

    /// Which mark sits on the Home Screen.
    ///
    /// The previews are drawn rather than loaded: an alternate icon lives in
    /// the asset catalog as an *icon*, which `UIImage(named:)` will not reliably
    /// hand back. Each one tints the one-colour mark (`AlohaMark`, the @ cut
    /// out) on the icon's sand ground, which is how the icons are recoloured
    /// too.
    struct AppIconPicker: View {
        @Environment(\.alohaPalette) private var palette

        @State private var current = UIApplication.shared.alternateIconName

        var body: some View {
            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                Text("App icon", comment: "Settings item")
                ScrollView(.horizontal) {
                    HStack(spacing: AlohaMetrics.space3) {
                        ForEach(AlohaIconVariant.allCases) { choice in
                            Button {
                                select(choice)
                            } label: {
                                IconPreview(
                                    accent: choice,
                                    isSelected: current == Self.iconName(for: choice))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(choice.displayName))
                            .accessibilityAddTraits(
                                current == Self.iconName(for: choice)
                                    ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.vertical, AlohaMetrics.space1)
            .sensoryFeedback(.selection, trigger: current)
        }

        /// `nil` is the primary icon; every other name matches an icon set in
        /// the catalog and the build setting that lists them.
        private static func iconName(for accent: AlohaIconVariant) -> String? {
            accent == .aloha ? nil : "AlohaIcon-\(accent.rawValue.capitalized)"
        }

        private func select(_ accent: AlohaIconVariant) {
            let name = Self.iconName(for: accent)
            guard UIApplication.shared.supportsAlternateIcons, name != current else { return }
            UIApplication.shared.setAlternateIconName(name) { error in
                Task { @MainActor in
                    // A refusal leaves the Home Screen as it was; the picker
                    // has to agree with it rather than show the choice.
                    current = error == nil ? name : UIApplication.shared.alternateIconName
                }
            }
        }
    }

    /// The mark, drawn small: sand ground, hibiscus in the variant's colour.
    private struct IconPreview: View {
        let accent: AlohaIconVariant
        let isSelected: Bool

        var body: some View {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.984, green: 0.957, blue: 0.918))
                .frame(width: 60, height: 60)
                .overlay {
                    Image("AlohaMark", bundle: .module)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .foregroundStyle(accent.swatch)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.primary : Color.clear, lineWidth: 2.5
                        )
                        .padding(-3)
                }
        }
    }
#endif
