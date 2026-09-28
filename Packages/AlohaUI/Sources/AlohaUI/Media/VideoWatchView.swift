// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The watch page: the player pinned at the top, then the title, the channel
/// row with a follow button, a row of action pills, the description folded
/// away, and the comments (docs/06 §3).
public struct VideoWatchView: View {
    @Environment(\.alohaPalette) private var palette

    private let statusID: String
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var status: Status?
    /// What the server knows beyond Mastodon's shape: views, chapters, the
    /// dislike state. Decoded from the same bytes as the status.
    @State private var extras = VideoStatusExtras()
    @State private var comments: [Status] = []
    @State private var relationship: Relationship?
    @State private var isLoading = true
    @State private var isDescriptionExpanded = false
    @State private var errorMessage: String?
    @State private var seekRequest: Double?

    public init(
        statusID: String, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.statusID = statusID
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                player

                if let status {
                    let target = status.displayed
                    VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                        titleBlock(target)
                        if let video = extras.video { facts(video) }
                        channelRow(target)
                        actionPills(status)
                        if !chapters.isEmpty { chapterList }
                        description(status)
                        if let support = extras.video?.support, !support.isEmpty {
                            supportCard(support)
                        }
                        if extras.video?.download == false { downloadNote }
                        commentsSection
                    }
                    .padding(.horizontal, AlohaMetrics.space3)
                    .padding(.vertical, AlohaMetrics.space3)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, AlohaMetrics.space6)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                        .padding(AlohaMetrics.space3)
                }
            }
        }
        .background(palette.background)
        .navigationTitle(Text("Video", comment: "Watch screen title"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Player

    @ViewBuilder
    private var player: some View {
        if let target = status?.displayed, let attachment = target.mediaAttachments.first {
            let isCovered =
                target.sensitive
                && !session.settings.sensitiveMediaPolicy.allowsAutomaticReveal
            ZStack {
                Color.black
                if isCovered {
                    RemoteImage(url: attachment.previewURL, blurhash: attachment.blurhash)
                        .overlay(.ultraThinMaterial)
                        .overlay {
                            VStack(spacing: AlohaMetrics.space2) {
                                Image(systemName: AlohaSymbol.sensitive).font(.title)
                                Text("Sensitive content", comment: "Covered media title")
                            }
                            .foregroundStyle(.white)
                        }
                } else {
                    VideoAttachmentPlayer(
                        attachment: attachment, statusID: target.id,
                        apiBase: session.capabilities.apiBase,
                        autoplay: session.settings.autoplayVideo,
                        startsMuted: false,
                        seekRequest: $seekRequest)
                }
            }
            .aspectRatio(playerAspect(attachment), contentMode: .fit)
            .frame(maxWidth: .infinity)
        } else {
            Color.black
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }

    /// Wide video sits at 16:9; portrait video is capped at 4:5 so the page
    /// below it is still reachable without a long scroll.
    private func playerAspect(_ attachment: MediaAttachment) -> Double {
        min(max(attachment.displayAspectRatio, 0.8), 16 / 9)
    }

    // MARK: - Pieces

    private func titleBlock(_ target: Status) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            HStack(alignment: .firstTextBaseline, spacing: AlohaMetrics.space2) {
                if extras.video?.live == true { liveBadge }
                Text(VideoTitle.of(target))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            meta(target)
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
        }
    }

    private var liveBadge: some View {
        Text("Live", comment: "Watch page live badge")
            .font(AlohaType.micro.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                palette.destructive, in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .accessibilityLabel(Text("Live now", comment: "Watch page live badge accessibility"))
    }

    /// The row of facts a video app shows under the title: how many watched,
    /// what kind of thing it is, in which language, under which licence.
    private func facts(_ video: VideoDetails) -> some View {
        var items: [(symbol: String, text: Text)] = []
        if video.views > 0 {
            items.append(
                ("eye", Text("^[\(video.views) view](inflect: true)", comment: "Watch page fact")))
        }
        if video.likes > 0 {
            items.append(
                (
                    "hand.thumbsup",
                    Text("^[\(video.likes) like](inflect: true)", comment: "Watch page fact")
                ))
        }
        if video.dislikes > 0 {
            items.append(
                (
                    "hand.thumbsdown",
                    Text("^[\(video.dislikes) dislike](inflect: true)", comment: "Watch page fact")
                ))
        }
        if let category = video.category { items.append(("tag", Text(category))) }
        if let language = video.language {
            items.append(("character.bubble", Text(languageName(language))))
        }
        if let licence = video.licence { items.append(("doc.text", Text(licence))) }

        return ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: AlohaMetrics.space1) {
                        Image(systemName: item.symbol)
                        item.text
                    }
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .accessibilityElement(children: .combine)
    }

    /// PeerTube sends a language code; the person reads a language name.
    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    // MARK: - Chapters

    /// The server's chapters, else the ones written into the description.
    private var chapters: [VideoChapter] {
        if let served = extras.video?.chapters, !served.isEmpty { return served }
        guard let target = status?.displayed else { return [] }
        return VideoChapters.parse(from: StatusHTMLParser().plainText(target.content))
    }

    private var chapterList: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            Text("Chapters", comment: "Watch page section")
                .font(AlohaType.section)
            VStack(spacing: 0) {
                ForEach(chapters) { chapter in
                    Button {
                        seekRequest = chapter.start
                    } label: {
                        HStack(spacing: AlohaMetrics.space3) {
                            Text(VideoChapters.clock(chapter.start))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(palette.accent)
                                .frame(minWidth: 52, alignment: .leading)
                            Text(chapter.title)
                                .font(.subheadline)
                                .foregroundStyle(palette.label)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, AlohaMetrics.space3)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Text(
                            "\(chapter.title), at \(VideoChapters.clock(chapter.start))",
                            comment: "Watch page chapter accessibility label")
                    )
                    .accessibilityHint(Text("Jumps the video there", comment: "Accessibility hint"))
                }
            }
            .background(
                palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
        }
    }

    private func supportCard(_ support: String) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            Label {
                Text("Support the author", comment: "Watch page section")
            } icon: {
                Image(systemName: "heart.circle")
            }
            .font(AlohaType.section)
            Text(support)
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
                .textSelection(.enabled)
        }
        .padding(AlohaMetrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
    }

    private var downloadNote: some View {
        Label {
            Text("The author doesn't allow downloads of this video.", comment: "Watch page note")
        } icon: {
            Image(systemName: "arrow.down.circle.dotted")
        }
        .font(.caption)
        .foregroundStyle(palette.tertiaryLabel)
    }

    /// Counts and the date, as `Text` so the plural markup is resolved.
    private func meta(_ target: Status) -> Text {
        let date = Text(target.createdAt.formatted(date: .abbreviated, time: .omitted))
        let favourites = Text(
            "^[\(target.favouritesCount) favourite](inflect: true)", comment: "Watch page count")
        let boosts = Text(
            "^[\(target.reblogsCount) boost](inflect: true)", comment: "Watch page count")
        switch (target.favouritesCount > 0, target.reblogsCount > 0) {
        case (true, true):
            return Text("\(favourites) · \(boosts) · \(date)", comment: "Watch page meta line")
        case (true, false):
            return Text("\(favourites) · \(date)", comment: "Watch page meta line")
        case (false, true):
            return Text("\(boosts) · \(date)", comment: "Watch page meta line")
        case (false, false):
            return date
        }
    }

    private func channelRow(_ target: Status) -> some View {
        HStack(spacing: AlohaMetrics.space3) {
            Button {
                onAction(.openProfile(target.account))
            } label: {
                HStack(spacing: AlohaMetrics.space2) {
                    AvatarView(account: target.account, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(target.account.bestDisplayName)
                            .font(AlohaType.name)
                            .foregroundStyle(palette.label)
                            .lineLimit(1)
                        Text(
                            "^[\(target.account.followersCount) follower](inflect: true)",
                            comment: "Watch page channel line"
                        )
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: AlohaMetrics.space2)

            if target.account.id != session.snapshot.serverAccountID {
                followButton(target.account)
            } else if session.capabilities.isNextcloudSocial {
                // A channel is what a video belongs to everywhere but here;
                // your own video is where you get to your channels.
                NavigationLink(value: Route.channels) {
                    Text("Your channels", comment: "Watch page channel action")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.label)
                        .padding(.horizontal, AlohaMetrics.space4)
                        .padding(.vertical, AlohaMetrics.space2)
                        .background(palette.surfaceRaised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func followButton(_ account: Account) -> some View {
        let isFollowing = relationship?.following == true || relationship?.requested == true
        return Button {
            Task { await toggleFollow(account) }
        } label: {
            Group {
                if isFollowing {
                    Text("Following", comment: "Watch page follow state")
                } else {
                    Text("Follow", comment: "Watch page follow action")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isFollowing ? palette.label : palette.onAccent)
            .padding(.horizontal, AlohaMetrics.space4)
            .padding(.vertical, AlohaMetrics.space2)
            .background(
                isFollowing ? palette.surfaceRaised : palette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(relationship == nil)
    }

    private func actionPills(_ status: Status) -> some View {
        let target = status.displayed
        return ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space2) {
                pill(
                    symbol: target.favourited ? AlohaSymbol.favouriteFilled : AlohaSymbol.favourite,
                    title: Text(target.favouritesCount, format: .number.notation(.compactName)),
                    label: Text("Favourite", comment: "Status action"),
                    isOn: target.favourited, tint: palette.favourite
                ) { onAction(.favourite(status)) }

                if session.capabilities.isNextcloudSocial {
                    pill(
                        symbol: extras.disliked == true
                            ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                        title: Text(dislikeCount, format: .number.notation(.compactName)),
                        label: Text("Dislike", comment: "Status action"),
                        isOn: extras.disliked == true, tint: palette.destructive
                    ) { toggleDislike(status) }
                }

                pill(
                    symbol: AlohaSymbol.boost,
                    title: Text(target.reblogsCount, format: .number.notation(.compactName)),
                    label: Text("Boost", comment: "Status action"),
                    isOn: target.reblogged, tint: palette.boost
                ) { onAction(.boost(status)) }

                pill(
                    symbol: AlohaSymbol.reply, title: Text("Reply", comment: "Status action"),
                    label: Text("Reply", comment: "Status action")
                ) { onAction(.reply(status)) }

                pill(
                    symbol: AlohaSymbol.share, title: Text("Share", comment: "Status action"),
                    label: Text("Share", comment: "Status action")
                ) { onAction(.share(status)) }

                pill(
                    symbol: target.bookmarked ? AlohaSymbol.bookmarkFilled : AlohaSymbol.bookmark,
                    title: Text("Save", comment: "Watch page bookmark pill"),
                    label: Text("Bookmark", comment: "Status action"),
                    isOn: target.bookmarked, tint: palette.bookmark
                ) { onAction(.bookmark(status)) }

                Menu {
                    StatusMenu(status: status, onAction: onAction)
                } label: {
                    Image(systemName: AlohaSymbol.more)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.label)
                        .frame(width: 40, height: 36)
                        .background(palette.surfaceRaised, in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(Text("More actions", comment: "Status action"))
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func pill(
        symbol: String, title: Text, label: Text, isOn: Bool = false, tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AlohaMetrics.space1) {
                Image(systemName: symbol)
                    .foregroundStyle(isOn ? (tint ?? palette.accent) : palette.label)
                title
                    .foregroundStyle(palette.label)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, AlohaMetrics.space3)
            .frame(height: 36)
            .background(palette.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func description(_ status: Status) -> some View {
        let target = status.displayed
        let plain = StatusHTMLParser().plainText(target.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !plain.isEmpty || !target.tags.isEmpty {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isDescriptionExpanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    HStack {
                        Text("Description", comment: "Watch page section")
                            .font(AlohaType.section)
                        Spacer()
                        Image(systemName: isDescriptionExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryLabel)
                    }
                    RichTextView(status: status, lineLimit: isDescriptionExpanded ? nil : 2) {
                        onAction(.followLink($0))
                    }
                }
                .padding(AlohaMetrics.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    palette.surfaceRaised,
                    in: RoundedRectangle(
                        cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isDescriptionExpanded
                    ? Text("Collapse description", comment: "Watch page action")
                    : Text("Expand description", comment: "Watch page action"))
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            HStack(spacing: AlohaMetrics.space2) {
                Text("Comments", comment: "Watch page section")
                    .font(AlohaType.section)
                if !comments.isEmpty {
                    Text(comments.count, format: .number)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }
            }

            if let status {
                Button {
                    onAction(.reply(status))
                } label: {
                    HStack(spacing: AlohaMetrics.space2) {
                        AvatarView(account: session.snapshot.asAccount, size: 28)
                        Text("Add a comment…", comment: "Watch page comment field")
                            .font(.subheadline)
                            .foregroundStyle(palette.tertiaryLabel)
                        Spacer()
                    }
                    .padding(.horizontal, AlohaMetrics.space3)
                    .padding(.vertical, AlohaMetrics.space2)
                    .background(palette.surfaceRaised, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ForEach(comments) { comment in
                commentRow(comment)
            }

            if comments.isEmpty && !isLoading {
                Text("No comments yet.", comment: "Watch page empty comments")
                    .font(.footnote)
                    .foregroundStyle(palette.tertiaryLabel)
            }
        }
        .padding(.top, AlohaMetrics.space2)
    }

    private func commentRow(_ comment: Status) -> some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space2) {
            Button {
                onAction(.openProfile(comment.account))
            } label: {
                AvatarView(account: comment.account, size: 28)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AlohaMetrics.space1) {
                    Text(comment.account.bestDisplayName)
                        .font(.caption.weight(.semibold))
                    Text(PostAge.short(comment.createdAt))
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                }
                RichTextView(status: comment) { onAction(.followLink($0)) }
                    .font(.subheadline)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onAction(.open(comment)) }
        .contextMenu { StatusMenu(status: comment, onAction: onAction) }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let statusTask = session.client.send(Endpoint.statuses.status(statusID))
            async let contextTask = session.client.decode(
                StatusContext.self, from: Endpoint.statuses.context(statusID))
            let raw = try await statusTask
            let loaded = try AlohaJSON.decoder.decode(Status.self, from: raw.data)
            status = loaded
            // The same bytes carry the video facts; a status that has none
            // decodes to an empty set rather than failing.
            extras =
                (try? AlohaJSON.decoder.decode(VideoStatusExtras.self, from: raw.data))
                ?? VideoStatusExtras()
            comments = try await contextTask.descendants
            errorMessage = nil
            await loadRelationship(loaded.displayed.account)
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private var dislikeCount: Int {
        extras.dislikesCount ?? extras.video?.dislikes ?? 0
    }

    /// Optimistic, like the other toggles: the pill flips now, and the
    /// action layer tells the server.
    private func toggleDislike(_ status: Status) {
        let wasDisliked = extras.disliked == true
        extras.disliked = !wasDisliked
        extras.dislikesCount = max(0, dislikeCount + (wasDisliked ? -1 : 1))
        onAction(.dislike(status))
    }

    private func loadRelationship(_ account: Account) async {
        guard account.id != session.snapshot.serverAccountID else { return }
        relationship =
            (try? await session.client.decode(
                LossyArray<Relationship>.self,
                from: Endpoint.accounts.relationships([account.id])))?.elements.first
    }

    private func toggleFollow(_ account: Account) async {
        guard let current = relationship else { return }
        let wasFollowing = current.following || current.requested
        var optimistic = current
        optimistic.following = !wasFollowing
        optimistic.requested = false
        relationship = optimistic
        do {
            relationship = try await session.client.decode(
                Relationship.self,
                from: wasFollowing
                    ? Endpoint.accounts.simpleAction(account.id, "unfollow")
                    : Endpoint.accounts.follow(account.id))
        } catch {
            relationship = current
            await session.handle(error)
        }
    }
}
