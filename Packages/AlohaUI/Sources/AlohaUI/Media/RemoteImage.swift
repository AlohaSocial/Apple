// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaMedia
import AlohaModels
import SwiftUI

/// An image with a blurhash placeholder painted immediately, so nothing shifts
/// when the bytes arrive (docs/05 §3).
public struct RemoteImage<Placeholder: View>: View {
    @Environment(\.alohaPalette) private var palette

    private let url: URL?
    private let blurhash: String?
    private let contentMode: SwiftUI.ContentMode
    private let accessibilityText: String?
    private let placeholder: Placeholder

    @State private var image: CGImage?
    @State private var blurred: CGImage?

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
        GeometryReader { proxy in
            ZStack {
                if blurred == nil && image == nil {
                    if Placeholder.self == EmptyView.self {
                        palette.surfaceRaised
                    } else {
                        placeholder
                    }
                }
                if let blurred, image == nil {
                    Image(decorative: blurred, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                }
            }
            // A GeometryReader lays its child out top-leading; the image
            // belongs in the middle of the space it was given.
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task(id: url) {
                await load(size: proxy.size)
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHidden(accessibilityText == nil && url == nil)
    }

    private var accessibilityLabel: Text {
        if let accessibilityText, !accessibilityText.isEmpty { return Text(accessibilityText) }
        return Text(
            "Image without a description", comment: "Accessibility label for undescribed media")
    }

    private func load(size: CGSize) async {
        if let blurhash, blurred == nil {
            blurred = BlurHash.decode(blurhash, size: CGSize(width: 24, height: 24))
        }
        guard let url, size.width > 0, size.height > 0 else { return }
        let loaded = await ImageLoader.shared.image(for: url, targetSize: size)
        withAnimation(.easeOut(duration: 0.18)) { image = loaded }
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

    private let account: Account
    private let size: Double?

    public init(account: Account, size: Double? = nil) {
        self.account = account
        self.size = size
    }

    public var body: some View {
        let dimension = size ?? metrics.avatarSize
        RemoteImage(
            url: account.avatar, accessibilityText: nil,
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
