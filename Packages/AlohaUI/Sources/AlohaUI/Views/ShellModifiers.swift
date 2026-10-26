// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

// The modifiers the shell's screens wear: the reading column a timeline sits
// in on a wide screen, and a full-screen cover that is a sheet on the Mac.

extension View {
    /// A timeline on a regular-width shell is a reading column.
    ///
    /// Full window width runs a post's text to twelve hundred point, which is
    /// unreadable — the eye cannot find the start of the next line. Mail and
    /// Reader constrain their columns, and so does this: 820 points on iPad
    /// and 680 on Mac, centred, with the rest of the window quiet around it.
    /// In compact width — a phone, or an iPad in Slide Over or a narrow
    /// window — the screen is already a column and the constraint would only
    /// add margins, so it does nothing there. The size class decides, not
    /// the device: an iPad can be either.
    var readerColumn: some View {
        #if os(iOS)
            modifier(ReaderColumn(width: 820))
        #else
            modifier(ReaderColumn(width: 680))
        #endif
    }

    /// `fullScreenCover` does not exist on macOS; a sheet is the right
    /// equivalent there.
    @ViewBuilder
    func fullScreenCoverIfAvailable<Item: Identifiable, Content: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
            // A sheet, and macOS would run two sheets without it: a window
            // behind a sheet must be resizable to look like a normal window
            // at all, and the media viewer is full-screen on every other
            // platform, so it takes the window here.
            self.sheet(item: item, content: content)
        #else
            fullScreenCover(item: item, content: content)
        #endif
    }
}

/// The surrounding canvas must inherit the same theme as the reading surface.
private struct ReaderColumn: ViewModifier {
    @Environment(\.alohaPalette) private var palette
    #if !os(macOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    let width: CGFloat

    func body(content: Content) -> some View {
        if isCompact {
            content
        } else {
            content
                .frame(maxWidth: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .alohaWindowGround(palette)
        }
    }

    private var isCompact: Bool {
        #if os(macOS)
            false
        #else
            horizontalSizeClass == .compact
        #endif
    }
}
