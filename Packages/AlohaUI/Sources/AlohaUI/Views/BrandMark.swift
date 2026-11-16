// SPDX-License-Identifier: MIT

import SwiftUI

/// The Aloha Social mark — the "@ stamen hibiscus" — in its own colours.
///
/// Drawn from the vector in `Brand.xcassets`, which is the same artwork the app
/// icon is rendered from (`tools/icon-source`). The brand's coral, not the
/// server's accent: this is the app introducing itself, before any server has
/// said what colour it is.
struct BrandMark: View {
    var size: CGFloat = 96

    var body: some View {
        Image("AlohaMarkColour", bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#if os(macOS)
    import AppKit

    /// The app's own marks, for the Mac target, which draws them in places
    /// SwiftUI views do not reach.
    public enum AlohaBrand {
        /// The app's mark at the size of a menu bar item, as a template
        /// image: the one-colour hibiscus, which the menu bar tints for a
        /// light or dark bar itself.
        ///
        /// A `MenuBarExtra` label draws an image and a number and nothing
        /// else, so this is the image rather than a view.
        public static var menuBarImage: NSImage? {
            guard let mark = Bundle.module.image(forResource: "AlohaMark"),
                let image = mark.copy() as? NSImage
            else { return nil }
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
    }
#endif
