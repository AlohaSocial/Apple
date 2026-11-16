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
        #elseif os(visionOS)
            // A little wider than the Mac's: text is read from further away,
            // at a larger size, and the window is sized to the column
            // (`AlohaSocialApp`) rather than the column floating in it.
            modifier(ReaderColumn(width: 760))
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
    #if os(macOS)
        @Environment(\.alohaTranslucentWindow) private var isTranslucent
        /// The measure the reader chose, or zero for the default.
        @AppStorage(MacOptions.columnWidthKey) private var chosenWidth: Double = 0
        @State private var widthAtDragStart: Double?
    #endif
    #if !os(macOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    let width: CGFloat

    func body(content: Content) -> some View {
        if isCompact {
            content
        } else {
            #if os(macOS)
                if isTranslucent {
                    // Over the blurred desktop the column is a sheet of its
                    // own: rounded, lifted off the ground by a shadow, and
                    // clear of the window's edges — rather than a slab the
                    // height of the window with the desktop either side.
                    content
                        .frame(maxWidth: columnWidth)
                        .background(palette.background)
                        .clipShape(panel)
                        .overlay(alignment: .trailing) { resizeHandle }
                        .overlay(
                            panel.strokeBorder(palette.separator.opacity(0.35), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.32), radius: 22, y: 8)
                        .padding(.top, AlohaMetrics.space1)
                        .padding(.bottom, AlohaMetrics.space3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .alohaWindowGround(palette)
                } else {
                    plainColumn(content)
                }
            #else
                plainColumn(content)
            #endif
        }
    }

    #if os(macOS)
        private var panel: RoundedRectangle {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
        }
    #endif

    private func plainColumn(_ content: Content) -> some View {
        content
            #if os(macOS)
                .frame(maxWidth: columnWidth)
                .overlay(alignment: .trailing) { resizeHandle }
            #else
                .frame(maxWidth: width)
            #endif
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alohaWindowGround(palette)
    }

    #if os(macOS)
        private var columnWidth: CGFloat {
            chosenWidth > 0 ? chosenWidth : width
        }

        /// The column's trailing edge, to drag: a measure is a preference,
        /// and the edge of the thing is where a Mac expects to change it.
        /// The column is centred, so it grows both ways under the pointer.
        private var resizeHandle: some View {
            Color.clear
                .frame(width: 10)
                .contentShape(Rectangle())
                .onHover { isOver in
                    if isOver { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { drag in
                            let start = widthAtDragStart ?? Double(columnWidth)
                            widthAtDragStart = start
                            chosenWidth = min(max(start + drag.translation.width * 2, 460), 1100)
                        }
                        .onEnded { _ in widthAtDragStart = nil }
                )
                .help(
                    Text(
                        "Drag to change the column's width", comment: "Reading column resize handle"
                    ))
        }
    #endif

    private var isCompact: Bool {
        #if os(macOS)
            false
        #else
            horizontalSizeClass == .compact
        #endif
    }
}
