// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// How big the controls inside a post are drawn, and how far apart.
///
/// A timeline row packs its actions, poll options and reactions into the width
/// beside an avatar. A finger or a pointer hits 32pt there, and the row stays
/// one line. Eyes aim less finely: visionOS asks for targets of at least 44pt
/// with about 60pt between the centres of neighbours, and a look that lands
/// between two small targets picks neither. There the same controls grow and
/// spread; everywhere else nothing changes.
nonisolated enum RowTargets {
    #if os(visionOS)
        /// The height of a control in a row's action strip.
        static let height: Double = 44
        /// The smallest side of any control in a post; nothing below it.
        static let minimumSide: Double = 44
        /// Between a glyph and its number when each is its own control:
        /// 44 + 16 puts their centres 60pt apart.
        static let pairSpacing: Double = 16
        /// Between neighbouring chips and between poll options.
        static let chipSpacing: Double = AlohaMetrics.space3
        /// The glyph of a row action, and the font it is drawn in.
        static let glyphSide: Double = 22
        static let glyphFont: Font = .callout
    #else
        static let height: Double = 32
        static let minimumSide: Double = 0
        static let pairSpacing: Double = AlohaMetrics.space1
        static let chipSpacing: Double = AlohaMetrics.space2
        static let glyphSide: Double = 18
        static let glyphFont: Font = .footnote
    #endif
}
