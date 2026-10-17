// SPDX-License-Identifier: MIT

import AlohaMedia
import AlohaModels
import CoreGraphics
import Observation
import SwiftUI

/// The pictures behind custom emoji, loaded once and shared by every post,
/// name and content warning that shows them.
///
/// A `Text` can only hold an `Image` it already has, so a body draws its
/// shortcodes' space first and its pictures as they arrive; the first frame
/// is never held up waiting for a server's emoji.
@MainActor
@Observable
final class EmojiImages {
    static let shared = EmojiImages()

    private(set) var images: [URL: CGImage] = [:]
    /// A picture that would not load: the shortcode is drawn instead, as the
    /// server's own renderer does for an emoji it does not have.
    private(set) var failed: Set<URL> = []
    @ObservationIgnored private var requested: Set<URL> = []

    /// Pixels, not points: enough for a 3× screen at the largest text sizes
    /// without decoding the original, which can be a 1024px upload.
    private static let pixelSize = CGSize(width: 96, height: 96)

    static func url(of emoji: CustomEmoji) -> URL? {
        // The still frame when the server has one: an emoji in running text
        // is not worth an animation loop per row.
        emoji.staticURL ?? emoji.url
    }

    func image(for emoji: CustomEmoji) -> CGImage? {
        Self.url(of: emoji).flatMap { images[$0] }
    }

    func hasFailed(_ emoji: CustomEmoji) -> Bool {
        Self.url(of: emoji).map { failed.contains($0) } ?? true
    }

    func load(_ emojis: [CustomEmoji]) {
        for emoji in emojis {
            guard let url = Self.url(of: emoji), requested.insert(url).inserted else { continue }
            Task {
                if let image = await ImageLoader.shared.image(for: url, targetSize: Self.pixelSize)
                {
                    images[url] = image
                } else {
                    failed.insert(url)
                }
            }
        }
    }
}

extension Text {
    /// Several `Text`s as one, so a run of text and an emoji picture wrap and
    /// truncate together.
    ///
    /// Built as an interpolation rather than with `+`, which is deprecated,
    /// and not from a literal, which the string catalog would extract as a
    /// key of nothing but placeholders.
    static func concatenating(_ parts: [Text]) -> Text {
        var interpolation = LocalizedStringKey.StringInterpolation(
            literalCapacity: 0, interpolationCount: parts.count)
        for part in parts { interpolation.appendInterpolation(part) }
        return Text(LocalizedStringKey(stringInterpolation: interpolation))
    }

    /// A custom emoji drawn at the size of the text around it.
    static func emoji(_ image: CGImage, pointSize: CGFloat) -> Text {
        let scale = CGFloat(max(image.height, 1)) / max(pointSize, 1)
        return Text(Image(decorative: image, scale: scale))
            // A picture sits on the baseline; centred on the line it reads as
            // a letter rather than a raised badge.
            .baselineOffset(-pointSize * 0.2)
    }
}
