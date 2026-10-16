// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaMedia
import AlohaModels
import SwiftUI

/// An image with a blurhash placeholder painted immediately, so nothing shifts
/// when the bytes arrive (docs/05 §3).
///
/// It fills the space it is offered, like the `GeometryReader` it used to be
/// built on, but measures that space with `onGeometryChange` instead: a reader
/// per image is a layout container per image, and a timeline has a great many.
/// It decodes at the screen's own scale, so a 3× phone gets 3× pixels.
public struct RemoteImage<Placeholder: View>: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.displayScale) private var displayScale

    private let url: URL?
    private let blurhash: String?
    private let contentMode: SwiftUI.ContentMode
    private let accessibilityText: String?
    private let placeholder: Placeholder

    @State private var image: CGImage?
    @State private var blurred: CGImage?
    @State private var loadedURL: URL?
    @State private var size: CGSize = .zero

    private struct LoadKey: Hashable {
        let url: URL?
        let width: Int
        let height: Int
        let scale: Double
    }

    /// `placeholder` is what shows when there is neither an image nor a
    /// blurhash — an avatar's monogram, say, rather than an empty grey circle.
    public init(
        url: URL?, blurhash: String? = nil,
        contentMode: SwiftUI.ContentMode = .fill, accessibilityText: String? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.blurhash = blurhash
        self.contentMode = contentMode
        self.accessibilityText = accessibilityText
        self.placeholder = placeholder()
    }

    public var body: some View {
        // `Color.clear` takes the whole proposal, exactly as the reader did;
        // the layers draw over it, centred, and are clipped to it.
        Color.clear
            .overlay {
                ZStack {
                    let placeholderImage = blurred ?? cachedBlur
                    if placeholderImage == nil && image == nil {
                        if Placeholder.self == EmptyView.self {
                            palette.surfaceRaised
                        } else {
                            placeholder
                        }
                    }
                    if let placeholderImage, image == nil {
                        Image(decorative: placeholderImage, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    }
                    if let image {
                        Image(decorative: image, scale: displayScale)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                            .transition(.opacity)
                    }
                }
            }
            .clipped()
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                size = $0
            }
            // The first layout can report 0×0. Including the measured size in
            // the identity retries after layout instead of leaving the
            // placeholder on screen for good.
            .task(id: loadKey) {
                await load()
            }
            // One element, whatever is drawn: the layers are decorative, the
            // description is what VoiceOver reads (docs/12 §3).
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHidden(accessibilityText == nil && url == nil)
    }

    private var loadKey: LoadKey {
        LoadKey(
            url: url,
            width: Int(size.width.rounded(.up)),
            height: Int(size.height.rounded(.up)),
            scale: displayScale)
    }

    /// A placeholder decoded for an earlier appearance, so a row scrolling
    /// back paints it in its first frame rather than a flat surface.
    private var cachedBlur: CGImage? {
        blurhash.flatMap { BlurHashCache.shared.cached($0) }
    }

    private var accessibilityLabel: Text {
        if let accessibilityText, !accessibilityText.isEmpty { return Text(accessibilityText) }
        return Text(
            "Image without a description", comment: "Accessibility label for undescribed media")
    }

    private func load() async {
        let size = size
        let scale = displayScale
        if loadedURL != url {
            image = nil
            blurred = nil
            loadedURL = url
        }
        guard let url, size.width > 0, size.height > 0 else {
            await loadPlaceholder()
            return
        }
        // Already decoded for this size: no fade, no placeholder frame.
        if let ready = ImageLoader.shared.memoryImage(for: url, targetSize: size, scale: scale) {
            image = ready
            return
        }
        await loadPlaceholder()
        let loaded = await ImageLoader.shared.image(for: url, targetSize: size, scale: scale)
        // A reused row may already represent a different URL by the time
        // the shared request finishes. Never replace its image with that result.
        guard !Task.isCancelled, loadedURL == url, let loaded else { return }
        withAnimation(.easeOut(duration: 0.18)) { image = loaded }
    }

    private func loadPlaceholder() async {
        guard let blurhash, blurred == nil, image == nil else { return }
        let decoded = await BlurHashCache.shared.placeholder(for: blurhash)
        guard !Task.isCancelled, image == nil else { return }
        blurred = decoded
    }
}

extension RemoteImage where Placeholder == EmptyView {
    public init(
        url: URL?, blurhash: String? = nil,
        contentMode: SwiftUI.ContentMode = .fill, accessibilityText: String? = nil
    ) {
        self.init(
            url: url, blurhash: blurhash, contentMode: contentMode,
            accessibilityText: accessibilityText, placeholder: { EmptyView() })
    }
}

/// An avatar, shaped by the person's preference.
public struct AvatarView: View {
    @Environment(\.alohaMetrics) private var metrics
    @Environment(\.alohaPalette) private var palette

    /// Avatars grow with Dynamic Type, so a face does not shrink to a dot
    /// next to accessibility-size names — but only so far: past half again
    /// its size an avatar takes the room the words need.
    @ScaledMetric(relativeTo: .body) private var typeScale: Double = 1

    private let account: Account
    private let size: Double?

    public init(account: Account, size: Double? = nil) {
        self.account = account
        self.size = size
    }

    /// The drawn size: the caller's (or the density's), scaled with text.
    static func dimension(base: Double, typeScale: Double) -> Double {
        (base * min(max(typeScale, 1), 1.5)).rounded()
    }

    public var body: some View {
        let dimension = Self.dimension(
            base: size ?? metrics.avatarSize, typeScale: typeScale)
        RemoteImage(
            // The static variant is smaller and avoids downloading an entire
            // animated avatar just to display its first frame.
            url: account.preferredAvatarURL, accessibilityText: nil,
            placeholder: { MonogramView(account: account, size: dimension) }
        )
        .frame(width: dimension, height: dimension)
        .clipShape(shape)
        .overlay(shape.stroke(palette.separator.opacity(0.6), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var shape: AnyShape {
        metrics.avatarShape == .circle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous))
    }
}
