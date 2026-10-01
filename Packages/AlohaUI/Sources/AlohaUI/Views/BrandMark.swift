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
