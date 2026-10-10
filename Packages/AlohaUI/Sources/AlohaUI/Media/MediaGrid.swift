// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaMedia
import AlohaModels
import SwiftUI

/// A status's attachments, laid out by count, obeying the reading policy for
/// sensitive media.
public struct MediaGrid: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.mediaTransition) private var mediaTransition

    private let attachments: [MediaAttachment]
    private let isSensitive: Bool
    private let policy: SensitiveMediaPolicy
    private let onOpen: (Int) -> Void

    @State private var isRevealed = false

    public init(
        attachments: [MediaAttachment], isSensitive: Bool,
        policy: SensitiveMediaPolicy, onOpen: @escaping (Int) -> Void
    ) {
        self.attachments = attachments
        self.isSensitive = isSensitive
        self.policy = policy
        self.onOpen = onOpen
    }

    public var body: some View {
        // `hide_all` is PeerTube's *hide*: not drawn, and no button to draw it —
        // opening the post is what it takes (docs/02 §2).
        if shouldCover && policy == .hideAll {
            hiddenNotice
        } else {
            ZStack {
                grid
                if shouldCover && !isRevealed { cover }
            }
            .clipShape(
                RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
            )
            // A shadow rather than an outline: one line fewer, and a pale
            // photograph still lifts off the page. Tight to the picture — a
            // softer, further-reaching one washed over the row beneath it.
            .shadow(color: shadowTint, radius: 5, y: 2)
        }
    }

    /// The photograph's own average colour, so the shadow under it belongs to
    /// the picture rather than being a generic grey.
    private var shadowTint: Color {
        guard let hash = attachments.first?.blurhash,
            let average = BlurHash.averageColour(hash)
        else { return .black.opacity(0.10) }
        return Color(red: average.red, green: average.green, blue: average.blue).opacity(0.18)
    }

    /// Nothing in a row is drawn taller than 4:5, and never taller than this.
    static let minimumRowAspect: Double = 0.8
    static let maximumRowHeight: Double = 300

    private var shouldCover: Bool {
        isSensitive && !policy.allowsAutomaticReveal
    }

    @ViewBuilder
    private var grid: some View {
        switch attachments.count {
        case 0:
            EmptyView()
        case 1:
            // A portrait video at its true aspect swallows the screen. The
            // row shows it at a bounded height; the viewer shows it whole.
            cell(attachments[0], index: 0)
                .aspectRatio(
                    max(attachments[0].displayAspectRatio, Self.minimumRowAspect),
                    contentMode: .fit
                )
                .frame(maxHeight: Self.maximumRowHeight)
        case 2:
            HStack(spacing: 2) {
                cell(attachments[0], index: 0)
                cell(attachments[1], index: 1)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
        default:
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)],
                spacing: 2
            ) {
                ForEach(Array(attachments.prefix(4).enumerated()), id: \.element.id) {
                    index, attachment in
                    cell(attachment, index: index)
                        .aspectRatio(1, contentMode: .fill)
                }
            }
        }
    }

    private func cell(_ attachment: MediaAttachment, index: Int) -> some View {
        Button {
            onOpen(index)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(
                    url: attachment.displayImageURL,
                    blurhash: attachment.blurhash,
                    accessibilityText: attachment.description
                )

                if attachment.type.isPlayable {
                    Image(systemName: AlohaSymbol.play)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.45), in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }

                // An ALT badge appears only where a description genuinely
                // exists — never a fake one (docs/06 §8).
                if attachment.hasAltText {
                    Text("ALT", comment: "Badge on media that carries alt text")
                        .font(AlohaType.micro.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .mediaTransitionSource(id: attachment.id, in: mediaTransition)
        .accessibilityLabel(
            attachment.description.map { Text($0) }
                ?? Text("Media without a description", comment: "Accessibility label")
        )
        .accessibilityAddTraits(.isButton)
    }

    private var cover: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: AlohaMetrics.space2) {
                Image(systemName: AlohaSymbol.sensitive)
                    .font(.title2)
                Text("Sensitive content", comment: "Cover over sensitive media")
                    .font(.subheadline.weight(.medium))
                Text("Tap to show", comment: "Cover over sensitive media, action hint")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { isRevealed = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("Sensitive content. Double-tap to show.", comment: "Accessibility")
        )
        .accessibilityAddTraits(.isButton)
    }

    private var hiddenNotice: some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.sensitive)
            Text("Media hidden by your settings", comment: "hide_all policy notice")
                .font(.footnote)
        }
        .foregroundStyle(palette.secondaryLabel)
        .padding(.vertical, AlohaMetrics.space2)
    }
}
