// SPDX-License-Identifier: MIT

import CoreGraphics
import SwiftUI

/// The size a media window opens at: the shape of the picture or video it
/// starts on, so the media fills the glass rather than sitting in a 16:10
/// pane with bars down its sides.
///
/// The long edge is fixed and the short one follows the media, within limits:
/// a panorama or a phone-tall screenshot would otherwise open as a ribbon.
/// Without dimensions — a remote post that sent no `meta` — the window opens
/// at the landscape size every media window used to open at.
nonisolated enum MediaWindowSizing {
    /// The long edge of a landscape window, in points.
    static let landscapeWidth: CGFloat = 1280
    /// The long edge of a portrait window: shorter than a landscape one,
    /// because a window that tall reaches past where the eyes rest.
    static let portraitHeight: CGFloat = 1000
    /// The short edge never drops below this, whatever the media's shape.
    static let shortestEdge: CGFloat = 480
    /// The smallest a person can make it by hand.
    static let minimum = CGSize(width: 360, height: 280)

    static func idealSize(aspect: Double?) -> CGSize {
        guard let aspect, aspect.isFinite, aspect > 0 else {
            return CGSize(width: landscapeWidth, height: 800)
        }
        if aspect >= 1 {
            let height = max(shortestEdge, (landscapeWidth / aspect).rounded())
            return CGSize(width: landscapeWidth, height: height)
        }
        let width = max(shortestEdge, (portraitHeight * aspect).rounded())
        return CGSize(width: width, height: portraitHeight)
    }
}

#if os(visionOS)
    extension View {
        /// A media window's content, sized to the media it opens on.
        ///
        /// The ideal size is what the app's `defaultWindowPlacement` measures
        /// (`sizeThatFits(.unspecified)`) to open the window; the minimum and
        /// the open maximum are what `.windowResizability(.contentSize)` lets
        /// a person drag it between.
        public func mediaWindowFrame(for request: MediaWindowRequest?) -> some View {
            let start = request.flatMap { request in
                request.attachments.indices.contains(request.index)
                    ? request.attachments[request.index] : request.attachments.first
            }
            let ideal = MediaWindowSizing.idealSize(aspect: start?.aspectRatio)
            return frame(
                minWidth: MediaWindowSizing.minimum.width, idealWidth: ideal.width,
                maxWidth: .infinity,
                minHeight: MediaWindowSizing.minimum.height, idealHeight: ideal.height,
                maxHeight: .infinity)
        }
    }
#endif
