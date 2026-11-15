// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

#if os(iOS)
    import UIKit

    /// Which mark sits on the Home Screen.
    ///
    /// An alternate icon lives in the asset catalog as an *icon*, which
    /// `UIImage(named:)` will not reliably hand back, so `tools/make-icons.sh`
    /// writes each one out a second time as an ordinary preview image
    /// (`AppIconPreview-…`). Where that is missing — a build whose catalog
    /// has not been regenerated — the preview is drawn instead: the
    /// one-colour mark (`AlohaMark`, the @ cut out) tinted on the icon's
    /// ground, which is how the icons are recoloured too.
    ///
    /// iOS and iPadOS only: the Mac has no alternate app icons, and its Dock
    /// icon is the app bundle's.
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
                                    isSelected: current == choice.alternateIconName)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(choice.displayName))
                            .accessibilityAddTraits(
                                current == choice.alternateIconName
                                    ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.vertical, AlohaMetrics.space1)
            .alohaSensoryFeedback(.selection, trigger: current)
        }

        /// `nil` is the primary icon; every other name matches an icon set in
        /// the catalog and `ALOHA_ALTERNATE_APP_ICONS` in Supporting/Aloha.xcconfig.
        private func select(_ accent: AlohaIconVariant) {
            let name = accent.alternateIconName
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
        @Environment(\.alohaPalette) private var palette

        let accent: AlohaIconVariant
        let isSelected: Bool

        var body: some View {
            RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                .fill(accent.ground)
                .frame(width: 60, height: 60)
                .overlay {
                    if let preview = UIImage(named: accent.previewImageName) {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
                    } else {
                        Image("AlohaMark", bundle: .module)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .foregroundStyle(accent.swatch)
                    }
                }
                // A hairline, so the paler tiles do not melt into a light
                // Settings page.
                .overlay {
                    RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                        .strokeBorder(palette.separator, lineWidth: 0.5)
                }
                // Drawn inside the frame: a ring that hung outside the tile
                // overlapped its neighbour at the spacing this row uses.
                .overlay {
                    if isSelected {
                        RoundedRectangle(
                            cornerRadius: AlohaMetrics.cornerMedium, style: .continuous
                        )
                        .strokeBorder(palette.label, lineWidth: 2.5)
                    }
                }
        }
    }
#endif
