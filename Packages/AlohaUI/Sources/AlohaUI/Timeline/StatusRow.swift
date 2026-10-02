// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

public struct StatusRow: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics
    @Environment(AppEnvironment.self) private var environment

    private let status: Status
    private let policy: SensitiveMediaPolicy
    private let localHost: String?
    private let filterWarning: String?
    private let showActions: Bool
    private let showsContextLine: Bool
    private let canReact: Bool
    private let isOwn: Bool
    private let onAction: (StatusRowAction) -> Void

    @State private var isSpoilerRevealed = false
    @State private var isFilterRevealed = false
    /// A quoted post fetched by id, when the server sent only `quote_id`.
    @State private var fetchedQuote: Status?

    public init(
        status: Status,
        policy: SensitiveMediaPolicy,
        localHost: String?,
        filterWarning: String? = nil,
        showActions: Bool = true,
        showsContextLine: Bool = true,
        canReact: Bool = false,
        isOwn: Bool = false,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.status = status
        self.policy = policy
        self.localHost = localHost
        self.filterWarning = filterWarning
        self.showActions = showActions
        self.showsContextLine = showsContextLine
        self.canReact = canReact
        self.isOwn = isOwn
        self.onAction = onAction
    }

    private var displayed: Status { status.displayed }

    public var body: some View {
        Group {
            if let filterWarning, !isFilterRevealed {
                filteredPlaceholder(filterWarning)
            } else {
                content
            }
        }
    }

    /// How much of the page this row is entitled to.
    ///
    /// Every row used to weigh the same: a one-line reply, a boost of somebody
    /// else's post, and a post carrying a 300pt video all had the same padding
    /// and the same colour. Weight now follows what the row actually is.
    private enum Emphasis {
        /// Somebody else's post, passed along. Quieter.
        case quiet
        /// An ordinary post.
        case standard
        /// A post carrying media, which needs room around it.
        case rich
    }

    private var emphasis: Emphasis {
        if status.booster != nil { return .quiet }
        if !displayed.mediaAttachments.isEmpty || displayed.poll != nil { return .rich }
        return .standard
    }

    private var verticalPadding: Double {
        switch emphasis {
        case .quiet: metrics.density.rowPadding * 0.75
        case .standard: metrics.density.rowPadding
        case .rich: metrics.density.rowPadding * 1.35
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: metrics.density.rowSpacing) {
            // One context line, never two — and none at all in a thread, where
            // the nesting already says what it would say.
            if showsContextLine, let context = contextLine {
                contextRow(context)
            }

            HStack(alignment: .top, spacing: AlohaMetrics.space3) {
                Button {
                    onAction(.openProfile(displayed.account))
                } label: {
                    AvatarView(
                        account: displayed.account,
                        size: emphasis == .quiet ? metrics.avatarSize * 0.82 : nil)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    header
                    if displayed.hasContentWarning { spoilerRow }
                    if !displayed.hasContentWarning || isSpoilerRevealed { statusBody }
                    if showActions { actionRow }
                }
            }
        }
        .padding(.vertical, verticalPadding)
        // Your own posts carry a rule in the accent down their leading edge —
        // enough to find yourself in a timeline, not enough to shout.
        .overlay(alignment: .leading) {
            if isOwn {
                Capsule()
                    .fill(palette.accent.opacity(0.55))
                    .frame(width: 3)
                    .padding(.vertical, verticalPadding * 0.6)
                    .offset(x: -AlohaMetrics.space3)
            }
        }
        .opacity(emphasis == .quiet ? 0.92 : 1)
        .contentShape(Rectangle())
        .onTapGesture { onAction(.open(status)) }
        // The whole row reads as one element; the actions are custom actions
        // rather than six separate stops (docs/12 §3).
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("status.\(displayed.id)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityActions { accessibilityActions }
    }

    // MARK: - Pieces

    private var contextLine: (symbol: String, text: Text, tint: Color)? {
        if let booster = status.booster {
            return (
                AlohaSymbol.boost,
                Text("Boosted by \(booster.bestDisplayName)", comment: "Timeline context line"),
                palette.boost
            )
        }
        if displayed.pinned {
            return (
                AlohaSymbol.pin, Text("Pinned", comment: "Timeline context line"),
                palette.secondaryLabel
            )
        }
        if let replyTo = displayed.inReplyToAccountID {
            // A self-reply is a thread continuation, and Mastodon omits the
            // self-mention — so looking only in `mentions` made your own
            // threads read as unrelated top-level posts.
            if replyTo == displayed.account.id {
                return (
                    "text.append",
                    Text("Continued thread", comment: "Timeline context line"),
                    palette.secondaryLabel
                )
            }
            if let mention = displayed.mentions.first(where: { $0.id == replyTo }) {
                return (
                    AlohaSymbol.reply,
                    Text("Replying to @\(mention.acct)", comment: "Timeline context line"),
                    palette.secondaryLabel
                )
            }
            // Replying to somebody this status does not name. Still worth
            // saying it is a reply.
            return (
                AlohaSymbol.reply,
                Text("Replying", comment: "Timeline context line"),
                palette.secondaryLabel
            )
        }
        return nil
    }

    private func contextRow(_ context: (symbol: String, text: Text, tint: Color)) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: context.symbol)
                .font(.caption)
            context.text
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(context.tint)
        .padding(.leading, metrics.avatarSize + AlohaMetrics.space3)
    }

    private var header: some View {
        HStack(spacing: AlohaMetrics.space2) {
            Button {
                onAction(.openProfile(displayed.account))
            } label: {
                HStack(spacing: AlohaMetrics.space2) {
                    Text(displayed.account.bestDisplayName)
                        .font(AlohaType.name)
                        .foregroundStyle(palette.label)
                        .lineLimit(1)

                    if displayed.account.bot {
                        Image(systemName: "gearshape.2")
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryLabel)
                            .accessibilityLabel(Text("Automated account", comment: "Bot badge"))
                    }

                    // The host shows whenever it differs from the reading
                    // account's, so two Alices stay distinguishable.
                    Text(displayed.account.qualifiedHandle(localHost: localHost))
                        .font(AlohaType.meta)
                        .foregroundStyle(palette.tertiaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: AlohaMetrics.space2)

            Text(PostAge.short(displayed.createdAt))
                .font(AlohaType.meta)
                .foregroundStyle(palette.tertiaryLabel)
                .lineLimit(1)

            if displayed.isEdited {
                Image(systemName: AlohaSymbol.edit)
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryLabel)
                    .accessibilityLabel(Text("Edited", comment: "Edited badge"))
            }

            visibilityBadge
        }
    }

    @ViewBuilder
    private var visibilityBadge: some View {
        switch displayed.visibility {
        case .private:
            Image(systemName: AlohaSymbol.lock).font(.caption2).foregroundStyle(
                palette.tertiaryLabel)
        case .direct:
            Image(systemName: AlohaSymbol.envelope).font(.caption2).foregroundStyle(
                palette.tertiaryLabel)
        case .unlisted:
            Image(systemName: "eye.slash").font(.caption2).foregroundStyle(palette.tertiaryLabel)
        case .public, .unknownCase:
            EmptyView()
        }
    }

    /// A content warning collapses the body **and** the media, both.
    private var spoilerRow: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isSpoilerRevealed.toggle() }
        } label: {
            HStack(spacing: AlohaMetrics.space2) {
                Image(systemName: AlohaSymbol.warning)
                Text(displayed.spoilerText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: isSpoilerRevealed ? "chevron.up" : "chevron.down")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(palette.label)
            .padding(AlohaMetrics.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var statusBody: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            RichTextView(status: status) { link in
                onAction(.followLink(link))
            }

            if !displayed.mediaAttachments.isEmpty {
                MediaGrid(
                    attachments: displayed.mediaAttachments,
                    isSensitive: displayed.sensitive,
                    policy: policy
                ) { index in
                    onAction(.openMedia(status: displayed, index: index))
                }
            }

            if let poll = displayed.poll {
                PollView(poll: poll) { choices in
                    onAction(.vote(pollID: poll.id, choices: choices))
                }
            }

            if displayed.mediaAttachments.isEmpty, let card = displayed.card, card.url != nil {
                LinkCardView(card: card) { onAction(.openCard(card)) }
            }

            if let quoted = displayed.quotedStatus ?? fetchedQuote {
                QuotedStatusCard(status: quoted, localHost: localHost) {
                    onAction(.open(quoted))
                }
            } else if displayed.quoteID != nil, displayed.quote?.state != "revoked" {
                Color.clear.frame(height: 1)
                    .task(id: displayed.quoteID) { await fetchQuote() }
            }

            if displayed.quote?.state == "revoked" || displayed.quote?.state == "rejected" {
                Text("The quoted post was withdrawn.", comment: "Quote state")
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.tertiaryLabel)
            }

            if let place = displayed.place { placeChip(place) }

            if displayed.archived == true { archivedBadge }

            if canReact || !(displayed.reactions ?? []).isEmpty {
                ReactionRow(reactions: displayed.reactions ?? [], canAdd: canReact) { name, isOn in
                    onAction(.react(status: status, name: name, add: !isOn))
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 0) {
            StatusActionButton(
                symbol: AlohaSymbol.reply, count: displayed.repliesCount,
                tint: palette.secondaryLabel, isOn: false, style: .plain,
                label: Text("Reply", comment: "Status action")
            ) { onAction(.reply(status)) }

            StatusActionButton(
                symbol: AlohaSymbol.boost, count: displayed.reblogsCount,
                tint: palette.boost, isOn: displayed.reblogged, style: .spin,
                label: Text("Boost", comment: "Status action")
            ) { onAction(.boost(status)) }

            StatusActionButton(
                symbol: displayed.favourited ? AlohaSymbol.favouriteFilled : AlohaSymbol.favourite,
                count: displayed.favouritesCount, tint: palette.favourite,
                isOn: displayed.favourited, style: .pop,
                label: Text("Favourite", comment: "Status action")
            ) { onAction(.favourite(status)) }

            StatusActionButton(
                symbol: displayed.bookmarked ? AlohaSymbol.bookmarkFilled : AlohaSymbol.bookmark,
                count: nil, tint: palette.bookmark, isOn: displayed.bookmarked, style: .pop,
                label: Text("Bookmark", comment: "Status action")
            ) { onAction(.bookmark(status)) }

            // PeerTube's thumbs-down, only where a video carries one — and
            // **read-only**, because nothing can cast one from here.
            //
            // The server serialises `dislikes_count` and `disliked` on a video
            // status (`Stream::exportAsLocal`) and federates what PeerTube
            // sends, but no controller writes one: `DislikeService` is not
            // wired to a route. This was a button, and tapping it 404'd on
            // every federated PeerTube video. A count that says what the wider
            // network thinks is worth showing; a button that cannot work is
            // not (docs/06 §3).
            if displayed.mediaAttachments.contains(where: { $0.type.isPlayable }),
                displayed.dislikesCount > 0
            {
                StatusMetric(
                    symbol: "hand.thumbsdown",
                    count: displayed.dislikesCount,
                    label: Text(
                        "^[\(displayed.dislikesCount) dislike](inflect: true) elsewhere",
                        comment: "Read-only dislike count on a federated video"))
            }

            Spacer(minLength: 0)

            Menu {
                StatusMenu(status: status, onAction: onAction)
            } label: {
                Image(systemName: AlohaSymbol.more)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(Text("More actions", comment: "Status action"))
        }
        .padding(.top, AlohaMetrics.space1)
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: displayed.favourited)
        .animation(.spring(response: 0.42, dampingFraction: 0.7), value: displayed.reblogged)
    }

    private func placeChip(_ place: Status.StatusPlace) -> some View {
        NavigationLink(value: Route.place(id: place.id)) {
            Label {
                Text(place.label)
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
            .font(AlohaType.meta)
            .foregroundStyle(palette.secondaryLabel)
            .padding(.horizontal, AlohaMetrics.space2)
            .padding(.vertical, AlohaMetrics.space1)
            .background(palette.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text("Place: \(place.label)", comment: "Accessibility label for a place chip"))
    }

    private var archivedBadge: some View {
        Label {
            Text("Archived", comment: "Status badge")
        } icon: {
            Image(systemName: "archivebox")
        }
        .font(AlohaType.micro)
        .foregroundStyle(palette.tertiaryLabel)
    }

    /// Only when the server sent an id without the post. Cached per row; a
    /// failure leaves the row as it was rather than showing an error.
    private func fetchQuote() async {
        guard fetchedQuote == nil, let id = displayed.quoteID,
            let session = environment.activeSession
        else { return }
        fetchedQuote = try? await session.client.decode(
            Status.self, from: Endpoint.statuses.status(id))
    }

    private func filteredPlaceholder(_ title: String) -> some View {
        HStack(spacing: AlohaMetrics.space3) {
            Image(systemName: AlohaSymbol.sensitive)
                .foregroundStyle(palette.secondaryLabel)
            Text("Filtered: \(title)", comment: "Row hidden by a keyword filter")
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
            Spacer()
            Button {
                withAnimation { isFilterRevealed = true }
            } label: {
                Text("Show anyway", comment: "Reveal a filtered post")
            }
            .font(.footnote)
        }
        .padding(.vertical, AlohaMetrics.space3)
    }

    // MARK: - Accessibility

    /// The combined row replaces its children's labels, so the post itself has
    /// to be in here — a row that read only "Alice, 2 days ago" told VoiceOver
    /// nothing about what Alice said.
    private var accessibilityLabel: Text {
        let name = displayed.account.bestDisplayName
        let when = PostAge.spoken(displayed.createdAt)
        if displayed.hasContentWarning && !isSpoilerRevealed {
            return Text(
                "\(name), \(when), content warning: \(displayed.spoilerText)",
                comment: "Accessibility label for a status with a content warning")
        }
        var parts: [String] = []
        if let booster = status.booster {
            parts.append(
                String(
                    localized: "Boosted by \(booster.bestDisplayName)",
                    comment: "Accessibility boost context"))
        }
        parts.append(
            String(localized: "\(name), \(when)", comment: "Accessibility label for a status"))
        let body = StatusHTMLParser().plainText(displayed.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { parts.append(body) }
        let media = displayed.mediaAttachments.count
        if media > 0 {
            parts.append(
                String(
                    localized: "^[\(media) attachment](inflect: true)",
                    comment: "Accessibility media count"))
        }
        if displayed.poll != nil {
            parts.append(String(localized: "Poll", comment: "Accessibility poll marker"))
        }
        return Text(verbatim: parts.joined(separator: ". "))
    }

    @ViewBuilder
    private var accessibilityActions: some View {
        Button {
            onAction(.reply(status))
        } label: {
            Text("Reply", comment: "Accessibility action")
        }
        Button {
            onAction(.boost(status))
        } label: {
            Text("Boost", comment: "Accessibility action")
        }
        Button {
            onAction(.favourite(status))
        } label: {
            Text("Favourite", comment: "Accessibility action")
        }
        Button {
            onAction(.bookmark(status))
        } label: {
            Text("Bookmark", comment: "Accessibility action")
        }
        Button {
            onAction(.openProfile(displayed.account))
        } label: {
            Text("Open profile", comment: "Accessibility action")
        }
        Button {
            onAction(.report(status))
        } label: {
            Text("Report", comment: "Accessibility action")
        }
    }
}

/// A quoted post inside the quoting one: who, when, an excerpt, and the first
/// picture. Tapping opens the quoted post's thread.
struct QuotedStatusCard: View {
    @Environment(\.alohaPalette) private var palette

    let status: Status
    let localHost: String?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                HStack(spacing: AlohaMetrics.space2) {
                    AvatarView(account: status.account, size: 22)
                    Text(status.account.bestDisplayName)
                        .font(AlohaType.name)
                        .lineLimit(1)
                    Text(status.account.qualifiedHandle(localHost: localHost))
                        .font(AlohaType.meta)
                        .foregroundStyle(palette.tertiaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(PostAge.short(status.createdAt))
                        .font(AlohaType.meta)
                        .foregroundStyle(palette.tertiaryLabel)
                }

                if status.hasContentWarning {
                    Label {
                        Text(status.spoilerText)
                    } icon: {
                        Image(systemName: AlohaSymbol.warning)
                    }
                    .font(.footnote.weight(.medium))
                } else {
                    RichTextView(status: status, lineLimit: 4)
                        .font(.subheadline)
                }

                if let first = status.mediaAttachments.first {
                    RemoteImage(
                        url: first.displayImageURL, blurhash: first.blurhash,
                        accessibilityText: first.description
                    )
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(maxHeight: 160)
                    .clipShape(
                        RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                    )
                }
            }
            .padding(AlohaMetrics.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                    .strokeBorder(palette.separator, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(
                "Quoted post by \(status.account.bestDisplayName)",
                comment: "Accessibility label for a quote card"))
    }
}

public enum StatusRowAction: Sendable {
    case open(Status)
    /// The watch page rather than the thread: player first, comments under it.
    case watch(Status)
    case reply(Status)
    case boost(Status)
    case favourite(Status)
    case bookmark(Status)
    case openProfile(Account)
    case openMedia(status: Status, index: Int)
    case openCard(Card)
    case followLink(RichText.Link)
    case vote(pollID: String, choices: [Int])
    case react(status: Status, name: String, add: Bool)
    case report(Status)
    case share(Status)
    case translate(Status)
    case edit(Status)
    case delete(Status)
    case muteConversation(Status)
    case block(Account)
    case mute(Account)

    // Nextcloud Social extras.
    /// Archive or unarchive: off the profile, not deleted (Pixelfed's notion).
    case archive(Status)
    /// Pin to, or unpin from, the profile.
    case pin(Status)
    /// PeerTube's thumbs-down on a video.
    case dislike(Status)
    /// Open the composer quoting this post.
    case quote(Status)
    /// Where the post got to, server by server (author only).
    case showDelivery(Status)
    case showEditHistory(Status)
    /// Who may quote this post, and detaching quotes already made.
    case quoteControls(Status)
    /// Tag people in the photo.
    case tagPeople(Status)
    case addToCollection(Status)
    case addToList(Account)
}
