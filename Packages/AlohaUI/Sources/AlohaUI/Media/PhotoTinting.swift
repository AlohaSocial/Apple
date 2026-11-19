// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaMedia
import AlohaModels
import SwiftUI

/// Which picture a post's screen takes its tint from, and whether it may.
///
/// A photo post — one whose first attachment is a picture — and only while
/// that picture is on show. The colours of a photograph behind a content
/// warning, or of a sensitive one the reading policy covers, are a glimpse
/// of it, so those posts keep the plain page.
enum PhotoTintSource {
    static func attachment(
        of status: Status, policy: SensitiveMediaPolicy
    ) -> MediaAttachment? {
        let post = status.displayed
        guard !post.hasContentWarning else { return nil }
        if post.sensitive, policy != .showAll { return nil }
        guard let first = post.mediaAttachments.first, first.type == .image else { return nil }
        return first
    }

    /// Every address the picture may have been cached under, most likely
    /// first: the one rows and the viewer draw, then the others.
    static func cachedURLs(for attachment: MediaAttachment) -> [URL] {
        var urls: [URL] = []
        for url in [attachment.displayImageURL, attachment.previewURL, attachment.url] {
            if let url, !urls.contains(url) { urls.append(url) }
        }
        return urls
    }

    /// Whether a tint is drawn at all. Reduce Transparency and Increase
    /// Contrast both ask for the plainest, firmest grounds the app has, and
    /// so do the two high-contrast themes; under any of them the palette is
    /// left exactly as it is.
    static func allows(
        reduceTransparency: Bool, contrast: ColorSchemeContrast, theme: AlohaTheme? = nil
    ) -> Bool {
        guard !reduceTransparency, contrast != .increased else { return false }
        return theme != .highContrastLight && theme != .highContrastDark
    }

    /// The swatches as the arithmetic in `PhotoTint` takes them.
    static func swatches(_ colours: PhotoColours) -> [ServerAccent.RGB] {
        colours.swatches.map { ServerAccent.RGB(red: $0.red, green: $0.green, blue: $0.blue) }
    }
}

extension View {
    /// Finds the colours of `attachment` in what the app already holds —
    /// never by downloading — and hands them to `colours`, fading them in.
    /// `nil` clears them.
    func loadsPhotoColours(
        of attachment: MediaAttachment?, into colours: Binding<PhotoColours?>
    ) -> some View {
        task(id: attachment?.id) {
            guard let attachment else {
                colours.wrappedValue = nil
                return
            }
            let found = await PhotoColours.cached(
                imageURLs: PhotoTintSource.cachedURLs(for: attachment),
                blurhash: attachment.blurhash)
            guard !Task.isCancelled else { return }
            // A fade, not a movement: Reduce Motion has nothing to take away.
            withAnimation(.easeOut(duration: 0.4)) { colours.wrappedValue = found }
        }
    }

    /// The ground under a scrolling screen: the photograph's wash when there
    /// is one, the theme's own (`alohaGround`) otherwise.
    @ViewBuilder
    func photoTintGround(_ tint: PhotoTint?, palette: AlohaPalette) -> some View {
        if let tint {
            scrollContentBackground(.hidden)
                .background(PhotoTintGround(tint).ignoresSafeArea())
        } else {
            alohaGround(palette)
        }
    }
}
