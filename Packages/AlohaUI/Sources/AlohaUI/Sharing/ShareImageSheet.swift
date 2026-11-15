// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaMedia
import AlohaModels
import SwiftUI

/// "Share as image": the post drawn as a card (`PostImageCard`), previewed,
/// and handed to the system share sheet as a PNG.
///
/// What the card shows is decided once, from what the reader has already
/// seen (`PostImageDisclosure`); anything still hidden can be shown from
/// here, by the reader, and by nobody else.
struct ShareImageSheet: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let status: Status
    let session: AccountSession

    @State private var disclosure: PostImageDisclosure?
    @State private var file: PostImageFile?
    @State private var preview: CGImage?
    @State private var failed = false

    private var post: Status { status.displayed }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AlohaMetrics.space4) {
                    if let preview {
                        Image(decorative: preview, scale: 3)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: PostImageCard.width)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                            .accessibilityElement()
                            .accessibilityLabel(
                                Text(
                                    "Image of the post by \(post.account.bestDisplayName)",
                                    comment: "Share as image: preview accessibility label"))
                    } else if failed {
                        Text(
                            "The image could not be made.",
                            comment: "Share as image: rendering failed"
                        )
                        .foregroundStyle(palette.secondaryLabel)
                    } else {
                        ProgressView()
                            .frame(minHeight: 240)
                    }

                    if let disclosure, disclosure.hidesSomething(in: status) {
                        revealControl
                    }
                }
                .padding(AlohaMetrics.space4)
                .frame(maxWidth: .infinity)
            }
            .alohaGround(palette)
            .navigationTitle(Text("Share as image", comment: "Share as image: sheet title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", comment: "Sheet action")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let file {
                        ShareLink(
                            item: file,
                            preview: SharePreview(
                                Text(
                                    "Post by \(post.account.bestDisplayName)",
                                    comment: "Share as image: share sheet preview title"),
                                image: preview.map { Image(decorative: $0, scale: 3) }
                                    ?? Image(systemName: AlohaSymbol.share))
                        ) {
                            Label {
                                Text("Share", comment: "Share as image: share button")
                            } icon: {
                                Image(systemName: AlohaSymbol.share)
                            }
                        }
                    }
                }
            }
            .task(id: disclosure) {
                if disclosure == nil {
                    disclosure = PostImageDisclosure.decide(
                        for: status, policy: session.settings.sensitiveMediaPolicy,
                        spoilerRevealed: RevealedContent.shared.isSpoilerRevealed(post.id),
                        mediaRevealed: RevealedContent.shared.isMediaRevealed(
                            post.mediaAttachments.map(\.id)))
                    return
                }
                await render()
            }
        }
        .presentationDetents([.large])
    }

    /// Showing what is hidden is the reader's own act, made here, and it is
    /// remembered as if they had opened it in the timeline.
    private var revealControl: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            Text(
                "Content behind a warning or a sensitive picture stays hidden in the image.",
                comment: "Share as image: explanation of hidden content"
            )
            .font(.footnote)
            .foregroundStyle(palette.secondaryLabel)
            Button {
                RevealedContent.shared.setSpoiler(post.id, revealed: true)
                RevealedContent.shared.revealMedia(post.mediaAttachments.map(\.id))
                preview = nil
                file = nil
                disclosure = PostImageDisclosure(showsBody: true, showsMedia: true)
            } label: {
                Text("Show hidden content in the image", comment: "Share as image: reveal button")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: PostImageCard.width, alignment: .leading)
    }

    private func render() async {
        guard let disclosure else { return }
        let picture =
            disclosure.showsMedia
            ? post.mediaAttachments.first(where: { $0.type == .image }) : nil

        async let avatar: CGImage? =
            if let url = post.account.preferredAvatarURL {
                await ImageLoader.shared.image(
                    for: url, targetSize: CGSize(width: 44, height: 44), scale: 3)
            } else {
                nil
            }
        async let photo: CGImage? =
            if let url = picture?.displayImageURL {
                await ImageLoader.shared.image(
                    for: url, targetSize: CGSize(width: PostImageCard.width, height: 360),
                    scale: 3)
            } else {
                nil
            }
        let code = post.url.flatMap { PostQRCode.image(for: $0) }

        let text =
            disclosure.showsBody
            ? StatusHTMLParser().plainText(post.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let hidden: String? =
            if !disclosure.showsBody {
                String(
                    localized: "Hidden behind a content warning",
                    comment: "Share as image: stands in for text behind a content warning")
            } else if picture == nil, post.mediaAttachments.contains(where: { $0.type == .image }) {
                String(
                    localized: "Sensitive picture not shown",
                    comment: "Share as image: stands in for a covered sensitive picture")
            } else {
                nil
            }

        let card = PostImageCard(
            authorName: post.account.bestDisplayName,
            handle: handle,
            avatar: await avatar,
            spoiler: post.hasContentWarning ? post.spoilerText : nil,
            text: text,
            picture: await photo,
            pictureAspect: picture?.displayAspectRatio ?? 1,
            hiddenNotice: hidden,
            poll: disclosure.showsBody ? post.poll.map(PollResultsSummary.init) : nil,
            date: post.createdAt,
            host: post.url?.host() ?? session.snapshot.instanceHost,
            accent: palette.accent,
            code: code)

        guard !Task.isCancelled else { return }
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.cgImage, let png = PostImageFile.pngData(image) else {
            failed = true
            return
        }
        preview = image
        file = PostImageFile(png: png, name: "post-\(post.id).png")
    }

    /// `@name@host`, with the host written out even for a local account,
    /// because the picture travels where "local" means nothing.
    private var handle: String {
        let acct = post.account.acct
        if acct.contains("@") { return "@\(acct)" }
        let host = session.snapshot.instanceHost
        return host.isEmpty ? "@\(acct)" : "@\(acct)@\(host)"
    }
}
