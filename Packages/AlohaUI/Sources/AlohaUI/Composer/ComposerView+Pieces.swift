// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// The rows around the editor: what the post answers or quotes, its content
/// warning, place and video details, the card backgrounds, and how its
/// uploads and schedule stand.
extension ComposerView {
    // MARK: - Pieces

    /// Said before posting, not after: the favourites, boosts and replies the
    /// original gathered do not follow it to the new post.
    var redraftNote: some View {
        Label {
            Text(
                "Posting this deletes the original, with its favourites, boosts and replies.",
                comment: "Composer note when redrafting")
        } icon: {
            Image(systemName: "arrow.uturn.backward.circle")
        }
        .font(.caption)
        .foregroundStyle(palette.secondaryLabel)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space2)
        .background(palette.surfaceRaised)
    }

    /// The post being quoted, as a card the way it will sit under the new
    /// one. Nothing about it is editable here.
    func quoteCard(_ status: Status) -> some View {
        let target = status.displayed
        return HStack(alignment: .top, spacing: AlohaMetrics.space2) {
            Image(systemName: "text.quote")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
            VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                HStack(spacing: AlohaMetrics.space2) {
                    AvatarView(account: target.account, size: 22)
                    Text(target.account.bestDisplayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(target.account.qualifiedHandle(localHost: nil))
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                RichTextView(status: status, lineLimit: 3)
                    .font(.footnote)
                if !target.mediaAttachments.isEmpty {
                    Label {
                        Text(
                            "^[\(target.mediaAttachments.count) attachment](inflect: true)",
                            comment: "Quote card media count")
                    } icon: {
                        Image(systemName: AlohaSymbol.media)
                    }
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryLabel)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AlohaMetrics.space3)
        .background(palette.surfaceRaised)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("Quoting \(target.account.bestDisplayName)", comment: "Composer quote context"))
    }

    func placeChip(_ place: ComposerModel.ComposerPlace) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Label {
                Text(place.displayName)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
            .font(.footnote)
            .foregroundStyle(palette.accent)
            Spacer()
            Button {
                withAnimation { model.place = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(palette.tertiaryLabel)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove place", comment: "Composer action"))
        }
        .padding(.horizontal, AlohaMetrics.space4)
        .background(palette.surfaceRaised)
    }

    /// PeerTube-style metadata for a video, sent alongside the post so a
    /// federated PeerTube shows a title rather than the first line of text.
    var videoMetaFields: some View {
        VStack(spacing: AlohaMetrics.space2) {
            TextField(
                text: $model.videoTitle,
                prompt: Text("Video title", comment: "Composer video field placeholder")
            ) {
                Text("Video title", comment: "Composer video field label")
            }
            HStack(spacing: AlohaMetrics.space2) {
                TextField(
                    text: $model.videoCategory,
                    prompt: Text("Category", comment: "Composer video field placeholder")
                ) {
                    Text("Category", comment: "Composer video field label")
                }
                TextField(
                    text: $model.videoLicence,
                    prompt: Text("Licence", comment: "Composer video field placeholder")
                ) {
                    Text("Licence", comment: "Composer video field label")
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.footnote)
        .padding(AlohaMetrics.space3)
        .background(palette.surfaceRaised)
    }

    func replyContext(_ status: Status) -> some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.reply)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to @\(status.account.acct)", comment: "Composer reply context")
                    .font(.caption.weight(.medium))
                Text(status.account.bestDisplayName)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer()
        }
        .foregroundStyle(palette.secondaryLabel)
        .padding(AlohaMetrics.space3)
        .background(palette.surfaceRaised)
    }

    var contentWarningField: some View {
        TextField(
            text: $model.spoilerText,
            prompt: Text("Content warning", comment: "Composer field placeholder")
        ) {
            Text("Content warning", comment: "Composer field label")
        }
        .textFieldStyle(.plain)
        .padding(AlohaMetrics.space3)
        .background(palette.surfaceRaised)
    }

    /// What `/dice`, `/flip` and `/pick` will do when this goes out. A hint
    /// rather than a preview: the roll happens once, at the moment of posting,
    /// and showing a number here would be showing one that is not the one sent.
    var gamesHint: some View {
        HStack(spacing: AlohaMetrics.space2) {
            ForEach(model.pendingGames, id: \.self) { kind in
                Text(verbatim: kind.icon)
            }
            Text("Rolled when this goes out.", comment: "Composer games hint")
                .font(AlohaType.meta)
                .foregroundStyle(palette.secondaryLabel)
            Spacer()
        }
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.bottom, AlohaMetrics.space2)
        .accessibilityElement(children: .combine)
    }

    /// Six backgrounds for a short post, and the way back to plain text.
    var cardRow: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            Text("Post it as a card", comment: "Composer card section")
                .font(AlohaType.micro)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, AlohaMetrics.space4)

            ScrollView(.horizontal) {
                HStack(spacing: AlohaMetrics.space2) {
                    cardSwatch(nil)
                    ForEach(cardBackgrounds) { background in
                        cardSwatch(background)
                    }
                }
                .padding(.horizontal, AlohaMetrics.space4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, AlohaMetrics.space2)
    }

    private var cardBackgrounds: [TextCard.Background] {
        TextCard.backgrounds(accountHue: Monogram.hue(for: model.session.snapshot.qualifiedHandle))
    }

    @ViewBuilder
    private func cardSwatch(_ background: TextCard.Background?) -> some View {
        let isSelected = model.cardBackgroundID == background?.id
        Button {
            model.cardBackgroundID = isSelected ? nil : background?.id
        } label: {
            Group {
                if let background {
                    LinearGradient(
                        colors: [background.from, background.to],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    palette.surfaceRaised.overlay {
                        Image(systemName: "textformat")
                            .foregroundStyle(palette.secondaryLabel)
                    }
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall))
            .overlay {
                RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall)
                    .strokeBorder(
                        isSelected ? palette.accent : palette.separator,
                        lineWidth: isSelected ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            background.map { Text($0.name) }
                ?? Text("Plain text", comment: "Composer card option")
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    var uploadProgress: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            ForEach(model.uploader.progress.items) { item in
                HStack(spacing: AlohaMetrics.space2) {
                    Text(item.filename).font(.caption).lineLimit(1)
                    Spacer()
                    if item.failed {
                        Image(systemName: AlohaSymbol.warning).foregroundStyle(palette.destructive)
                    } else {
                        ProgressView(value: item.fractionCompleted).frame(width: 80)
                    }
                }
            }
        }
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space2)
        .background(palette.surfaceRaised)
    }

    func scheduleBanner(_ date: Date) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: "clock.fill")
            Text(
                "Scheduled for \(date.formatted(.dateTime.weekday().day().month().hour().minute()))",
                comment: "Composer schedule banner")
            Spacer()
            Button {
                model.scheduledAt = nil
            } label: {
                Text("Cancel", comment: "Composer schedule action")
            }
            .font(.caption)
        }
        .font(.caption)
        .foregroundStyle(palette.accent)
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space2)
        .background(palette.surfaceRaised)
    }

    func uploadError(_ message: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
            Text(message).font(.caption)
            Spacer()
        }
        .foregroundStyle(palette.destructive)
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space2)
    }
}
