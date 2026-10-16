// SPDX-License-Identifier: MIT

import CoreGraphics

/// The geometry of a zoomed photograph: how far it may be moved.
///
/// A zoomed picture moves under the finger the way Photos' does — as far as
/// its own edge and no further, so there is never empty black dragged into
/// view on a side the picture does not cover.
enum MediaZoom {
    /// The largest zoom a pinch reaches, and what a double tap goes to.
    static let maximum: CGFloat = 5
    static let doubleTap: CGFloat = 2.5

    /// The size a picture is drawn at when fitted into `container`, from its
    /// aspect ratio (width over height). Without one, the whole container.
    static func fittedSize(aspect: Double?, in container: CGSize) -> CGSize {
        guard let aspect, aspect > 0, container.width > 0, container.height > 0 else {
            return container
        }
        let ratio = CGFloat(aspect)
        if container.width / container.height > ratio {
            return CGSize(width: container.height * ratio, height: container.height)
        }
        return CGSize(width: container.width, height: container.width / ratio)
    }

    /// `proposed`, held inside the room a picture of `content` size has to
    /// move at `zoom` within `container`. At no zoom there is no room at all.
    static func clampedOffset(
        _ proposed: CGSize, zoom: CGFloat, content: CGSize, container: CGSize
    ) -> CGSize {
        let limit = CGSize(
            width: max(0, (content.width * zoom - container.width) / 2),
            height: max(0, (content.height * zoom - container.height) / 2))
        return CGSize(
            width: min(limit.width, max(-limit.width, proposed.width)),
            height: min(limit.height, max(-limit.height, proposed.height)))
    }
}
