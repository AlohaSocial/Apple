// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import Charts
import SwiftUI

/// A profile the way Nextcloud Social lays one out: banner, avatar with a
/// stories ring, name and handle, the note, the fields, featured hashtags, a
/// twelve-week rhythm strip, pinned posts, then the tabs — Posts, Replies,
/// Media, Videos, Albums and Tagged — all on one scrolling page (docs/05 §5).
public struct ProfileView: View {
    @Environment(\.alohaPalette) private var palette

    private let accountID: String
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var account: Account?
    @State private var relationship: Relationship?
    @State private var highlights: ProfileHighlights?
    @State private var featuredTags: [FeaturedTag] = []
    @State private var pinned: [Status] = []
    @State private var familiar: [Account] = []
    @State private var stories: [Story] = []
    @State private var collections: [Collection] = []
    @State private var tab: Tab = .posts
    @State private var errorMessage: String?
    @State private var noteDraft = ""
    @State private var isEditingNote = false
    @State private var isConfirmingDomainBlock = false
    @State private var isConfirmingRemoveFollower = false
    @State private var playingStoriesFrom: Int?

    enum Tab: String, CaseIterable, Identifiable {
        case posts, replies, media, videos, albums, tagged
        var id: String { rawValue }
    }

    public init(
        accountID: String, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.accountID = accountID
        self.session = session
        self.onAction = onAction
    }

    private var isOwn: Bool { accountID == session.snapshot.serverAccountID }

    private var availableTabs: [Tab] {
        var tabs: [Tab] = [.posts, .replies, .media, .videos]
        if session.capabilities.collections { tabs.append(.albums) }
        if session.capabilities.isNextcloudSocial { tabs.append(.tagged) }
        return tabs
    }

    public var body: some View {
        Group {
            if let account {
                content(account)
            } else if let errorMessage {
                ContentUnavailableView {
                    Text("Couldn't load this profile", comment: "Profile error title")
                } description: {
                    Text(errorMessage)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(account?.bestDisplayName ?? "")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
        .alert(
            Text("Note about this account", comment: "Account note alert title"),
            isPresented: $isEditingNote
        ) {
            TextField(
                String(localized: "Only you can see this", comment: "Account note placeholder"),
                text: $noteDraft)
            Button {
                Task { await saveNote() }
            } label: {
                Text("Save", comment: "Account note action")
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", comment: "Account note action")
            }
        }
        .confirmationDialog(
            Text("Block everyone on \(account?.host ?? "")?", comment: "Domain block title"),
            isPresented: $isConfirmingDomainBlock, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await blockDomain() }
            } label: {
                Text("Block domain", comment: "Domain block action")
            }
        } message: {
            Text(
                "You will not see posts from that server, and its people cannot follow you.",
                comment: "Domain block detail")
        }
        .confirmationDialog(
            Text("Remove this follower?", comment: "Remove follower title"),
            isPresented: $isConfirmingRemoveFollower, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await update(with: Endpoint.profile.removeFromFollowers(accountID)) }
            } label: {
                Text("Remove from followers", comment: "Remove follower action")
            }
        } message: {
            Text("They are not told, and can follow you again.", comment: "Remove follower detail")
        }
        .fullScreenCoverIfAvailable(
            item: Binding(
                get: { playingStoriesFrom.map { StoryStart(index: $0) } },
                set: { playingStoriesFrom = $0?.index })
        ) { start in
            StoryPlayer(stories: stories, startIndex: start.index, session: session)
        }
    }

    // MARK: - Layout

    private func content(_ account: Account) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                header(account)

                if !featuredTags.isEmpty { featuredTagChips }
                if let highlights, highlights.available { highlightsStrip(highlights) }
                if !pinned.isEmpty && tab == .posts { pinnedStrip }

                Section {
                    tabContent(account)
                } header: {
                    tabBar
                }
            }
        }
        .background(palette.background)
    }

    private var tabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space2) {
                ForEach(availableTabs) { option in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { tab = option }
                    } label: {
                        title(for: option)
                            .font(.subheadline.weight(tab == option ? .semibold : .regular))
                            .foregroundStyle(tab == option ? palette.onAccent : palette.label)
                            .padding(.horizontal, AlohaMetrics.space3)
                            .frame(minHeight: 44)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        .regular.tint(tab == option ? palette.accent : nil).interactive(),
                        in: Capsule())
                    .accessibilityAddTraits(tab == option ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, AlohaMetrics.space4)
            .padding(.vertical, AlohaMetrics.space2)
        }
        .scrollIndicators(.hidden)
        .background(palette.background)
    }

    private func title(for tab: Tab) -> Text {
        switch tab {
        case .posts: Text("Posts", comment: "Profile tab")
        case .replies: Text("Replies", comment: "Profile tab")
        case .media: Text("Media", comment: "Profile tab")
        case .videos: Text("Videos", comment: "Profile tab")
        case .albums: Text("Albums", comment: "Profile tab")
        case .tagged: Text("Tagged", comment: "Profile tab")
        }
    }

    @ViewBuilder
    private func tabContent(_ account: Account) -> some View {
        switch tab {
        case .posts:
            ProfileStatusList(
                key: TimelineKey(
                    mode: .home,
                    source: .account(id: accountID, includeReplies: false, onlyMedia: false)),
                session: session, onAction: onAction)
        case .replies:
            ProfileStatusList(
                key: TimelineKey(
                    mode: .home,
                    source: .account(id: accountID, includeReplies: true, onlyMedia: false)),
                session: session, onAction: onAction)
        case .media:
            ProfileStatusList(
                key: TimelineKey(
                    mode: .photos,
                    source: .account(id: accountID, includeReplies: false, onlyMedia: true)),
                session: session, onAction: onAction)
        case .videos:
            ProfileStatusList(
                key: TimelineKey(
                    mode: .video,
                    source: .account(id: accountID, includeReplies: false, onlyMedia: true)),
                session: session, onAction: onAction)
        case .albums:
            albumsGrid
        case .tagged:
            TaggedGrid(accountID: accountID, session: session, onAction: onAction)
                .padding(.top, AlohaMetrics.space2)
        }
    }

    // MARK: - Header

    private func header(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: account.preferredHeaderURL) {
                    // No banner: a gradient in the person's own colour rather
                    // than an empty grey band.
                    LinearGradient(
                        colors: [
                            Monogram.colour(for: account.acct, lightness: 0.46),
                            Monogram.colour(for: account.acct, lightness: 0.30),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .frame(height: 130)
                .clipped()

                avatar(account)
                    .padding(.leading, AlohaMetrics.space4)
                    .offset(y: 28)
            }
            .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: AlohaMetrics.space1) {
                            Text(account.bestDisplayName).font(AlohaType.display)
                            if account.locked {
                                Image(systemName: AlohaSymbol.lock)
                                    .font(.caption)
                                    .foregroundStyle(palette.tertiaryLabel)
                                    .accessibilityLabel(
                                        Text("Approves followers", comment: "Locked account badge"))
                            }
                            if account.bot {
                                Image(systemName: "gearshape.2")
                                    .font(.caption)
                                    .foregroundStyle(palette.tertiaryLabel)
                                    .accessibilityLabel(
                                        Text("Automated account", comment: "Bot badge"))
                            }
                        }
                        Text(account.qualifiedHandle(localHost: session.snapshot.instanceHost))
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryLabel)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    if isOwn {
                        NavigationLink(value: Route.editProfile) {
                            Text("Edit profile", comment: "Profile action")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        relationshipControls(account)
                    }
                }

                relationshipLine

                if !account.note.isEmpty {
                    RichTextView(
                        status: Status(
                            id: "note-\(account.id)", content: account.note, account: account)
                    ) { link in onAction(.followLink(link)) }
                }

                if !account.fields.isEmpty { fieldsTable(account) }

                if let note = relationship?.note, !note.isEmpty { privateNote(note) }

                stats(account)

                if !familiar.isEmpty { familiarLine }
            }
            .padding(.horizontal, AlohaMetrics.space4)
        }
        .padding(.bottom, AlohaMetrics.space2)
    }

    /// The ring is the same signal it is in Photos: an unseen story is bright,
    /// a seen one is quiet.
    private func avatar(_ account: Account) -> some View {
        let hasStories = !stories.isEmpty
        let allSeen = stories.allSatisfy(\.seen)
        return Button {
            if hasStories { playingStoriesFrom = 0 }
        } label: {
            AvatarView(account: account, size: 72)
                .padding(hasStories ? 3 : 0)
                .overlay {
                    if hasStories {
                        Circle().strokeBorder(
                            allSeen
                                ? AnyShapeStyle(palette.separator)
                                : AnyShapeStyle(
                                    AngularGradient(
                                        colors: [
                                            palette.accent, palette.favourite, palette.accent,
                                        ],
                                        center: .center)),
                            lineWidth: allSeen ? 1.5 : 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!hasStories)
        .accessibilityLabel(
            hasStories
                ? Text("Play \(account.bestDisplayName)'s stories", comment: "Profile stories ring")
                : Text("Profile picture", comment: "Profile avatar"))
    }

    @ViewBuilder
    private var relationshipLine: some View {
        if let relationship, !isOwn {
            HStack(spacing: AlohaMetrics.space2) {
                if relationship.followedBy {
                    badge(Text("Follows you", comment: "Relationship badge"))
                }
                if relationship.endorsed {
                    badge(Text("Featured on your profile", comment: "Relationship badge"))
                }
                if relationship.blocking {
                    badge(Text("Blocked", comment: "Relationship badge"))
                }
                if relationship.muting {
                    badge(Text("Muted", comment: "Relationship badge"))
                }
                if relationship.domainBlocking {
                    badge(Text("Domain blocked", comment: "Relationship badge"))
                }
            }
        }
    }

    private func badge(_ text: Text) -> some View {
        text
            .font(AlohaType.micro)
            .foregroundStyle(palette.secondaryLabel)
            .padding(.horizontal, AlohaMetrics.space2)
            .padding(.vertical, 3)
            .background(palette.surfaceRaised, in: Capsule())
    }

    private func privateNote(_ note: String) -> some View {
        Button {
            startEditingNote()
        } label: {
            HStack(alignment: .top, spacing: AlohaMetrics.space2) {
                Image(systemName: "note.text")
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your note", comment: "Private account note heading")
                        .font(AlohaType.micro)
                        .foregroundStyle(palette.secondaryLabel)
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(palette.label)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(AlohaMetrics.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                palette.accent.opacity(0.08),
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Your note: \(note). Edit", comment: "Private account note"))
    }

    private func stats(_ account: Account) -> some View {
        HStack(spacing: AlohaMetrics.space4) {
            stat(account.statusesCount, Text("Posts", comment: "Profile stat"))
            NavigationLink(value: Route.following(accountID: accountID)) {
                stat(account.followingCount, Text("Following", comment: "Profile stat"))
            }
            .buttonStyle(.plain)
            NavigationLink(value: Route.followers(accountID: accountID)) {
                stat(account.followersCount, Text("Followers", comment: "Profile stat"))
            }
            .buttonStyle(.plain)
        }
        .font(.footnote)
    }

    private func stat(_ value: Int, _ label: Text) -> some View {
        HStack(spacing: 4) {
            Text(value, format: .number.notation(.compactName))
                .fontWeight(.semibold)
                .fontDesign(.rounded)
            label.foregroundStyle(palette.secondaryLabel)
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }

    /// "Followed by Alice, Bob and 3 others you follow."
    private var familiarLine: some View {
        HStack(spacing: AlohaMetrics.space2) {
            HStack(spacing: -8) {
                ForEach(familiar.prefix(3)) { account in
                    AvatarView(account: account, size: 22)
                        .overlay(Circle().strokeBorder(palette.background, lineWidth: 1.5))
                }
            }
            familiarText
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private var familiarText: Text {
        let names = familiar.prefix(2).map(\.bestDisplayName)
        let rest = familiar.count - names.count
        let listed = Text(names.formatted(.list(type: .and)))
        if rest > 0 {
            let others = Text(
                "^[\(rest) other](inflect: true)", comment: "Familiar followers count")
            return Text(
                "Followed by \(listed) and \(others) you follow", comment: "Familiar followers line"
            )
        }
        return Text("Followed by \(listed), whom you follow", comment: "Familiar followers line")
    }

    private func fieldsTable(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            ForEach(Array(account.fields.enumerated()), id: \.offset) { _, field in
                HStack(alignment: .top, spacing: AlohaMetrics.space2) {
                    Text(field.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryLabel)
                        .frame(width: 96, alignment: .leading)
                    Text(
                        field.value
                            .replacingOccurrences(
                                of: "<[^>]+>", with: "", options: .regularExpression)
                    )
                    .font(.caption)
                    if field.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(palette.boost)
                            .accessibilityLabel(Text("Verified link", comment: "Profile field"))
                    }
                }
            }
        }
        .padding(AlohaMetrics.space3)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous))
    }

    // MARK: - Featured tags, highlights, pinned

    private var featuredTagChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space2) {
                ForEach(featuredTags) { tag in
                    NavigationLink(value: Route.hashtag(tag.name)) {
                        HStack(spacing: 4) {
                            Text(verbatim: "#\(tag.name)")
                                .font(.footnote.weight(.semibold))
                            if tag.statusesCount > 0 {
                                Text(tag.statusesCount, format: .number.notation(.compactName))
                                    .font(AlohaType.micro)
                                    .foregroundStyle(palette.secondaryLabel)
                            }
                        }
                        .foregroundStyle(palette.hashtag)
                        .padding(.horizontal, AlohaMetrics.space3)
                        .frame(minHeight: 32)
                        .background(palette.hashtag.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Text("Featured hashtag \(tag.name)", comment: "Featured tag chip"))
                }
            }
            .padding(.horizontal, AlohaMetrics.space4)
            .padding(.vertical, AlohaMetrics.space2)
        }
        .scrollIndicators(.hidden)
    }

    /// The twelve-week rhythm: a sparkline nobody has to read, and the
    /// sentence that reads it for them.
    private func highlightsStrip(_ highlights: ProfileHighlights) -> some View {
        HStack(alignment: .center, spacing: AlohaMetrics.space3) {
            VStack(alignment: .leading, spacing: 2) {
                if let since = highlights.since {
                    Text(
                        "Here since \(since.formatted(.dateTime.month(.wide).year()))",
                        comment: "Profile highlights join line"
                    )
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                }
                Text(
                    "^[\(highlights.total) post](inflect: true) in the last twelve weeks",
                    comment: "Profile highlights count"
                )
                .font(.footnote.weight(.medium))
                rhythmText(highlights.rhythm)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }
            Spacer(minLength: AlohaMetrics.space2)
            sparkline(highlights.weeks)
                .frame(width: 120, height: 32)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space2)
        .accessibilityElement(children: .combine)
    }

    private func rhythmText(_ rhythm: ProfileHighlights.Rhythm) -> Text {
        switch rhythm {
        case .quiet: Text("Quiet lately", comment: "Posting rhythm")
        case .busier: Text("Busier than usual", comment: "Posting rhythm")
        case .slowing: Text("Slowing down", comment: "Posting rhythm")
        case .steady: Text("Posting steadily", comment: "Posting rhythm")
        }
    }

    private func sparkline(_ weeks: [Int]) -> some View {
        let points = Array(weeks.enumerated())
        return Chart {
            ForEach(points, id: \.offset) { point in
                AreaMark(x: .value("Week", point.offset), y: .value("Posts", point.element))
                    .foregroundStyle(palette.accent.opacity(0.12))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Week", point.offset), y: .value("Posts", point.element))
                    .foregroundStyle(palette.accent)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if let last = points.last {
                PointMark(x: .value("Week", last.offset), y: .value("Posts", last.element))
                    .foregroundStyle(palette.accent)
                    .symbolSize(20)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }

    /// Pinned posts as a shelf: room for five without pushing the timeline
    /// below the fold.
    private var pinnedStrip: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            Label {
                Text("Pinned", comment: "Pinned posts section")
            } icon: {
                Image(systemName: AlohaSymbol.pin)
            }
            .font(AlohaType.section)
            .foregroundStyle(palette.secondaryLabel)
            .padding(.horizontal, AlohaMetrics.space4)

            ScrollView(.horizontal) {
                HStack(spacing: AlohaMetrics.space3) {
                    ForEach(pinned) { status in
                        pinnedCard(status)
                    }
                }
                .padding(.horizontal, AlohaMetrics.space4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, AlohaMetrics.space2)
    }

    private func pinnedCard(_ status: Status) -> some View {
        let target = status.displayed
        let plain = StatusHTMLParser().plainText(target.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            onAction(.open(status))
        } label: {
            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                Text(
                    target.hasContentWarning
                        ? target.spoilerText
                        : plain.isEmpty
                            ? String(localized: "Media post", comment: "Pinned card without text")
                            : plain
                )
                .font(.footnote)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
                HStack(spacing: AlohaMetrics.space2) {
                    if !target.mediaAttachments.isEmpty {
                        Image(systemName: AlohaSymbol.media).font(.caption2)
                    }
                    Text(PostAge.short(target.createdAt))
                        .font(AlohaType.meta)
                }
                .foregroundStyle(palette.tertiaryLabel)
            }
            .padding(AlohaMetrics.space3)
            .frame(width: 220, height: 120, alignment: .topLeading)
            .background(
                palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { StatusMenu(status: status, onAction: onAction) }
    }

    // MARK: - Albums tab

    private var albumsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: AlohaMetrics.space3)],
            spacing: AlohaMetrics.space3
        ) {
            ForEach(collections) { collection in
                NavigationLink {
                    CollectionDetailView(
                        session: session, collection: collection, onAction: onAction)
                } label: {
                    VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                        RemoteImage(url: collection.thumbnail)
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
                        Text(collection.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(
                            "^[\(collection.postCount) post](inflect: true)",
                            comment: "Album post count"
                        )
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AlohaMetrics.space3)
        .overlay {
            if collections.isEmpty {
                ContentUnavailableView {
                    Text("No albums", comment: "Empty collections")
                } description: {
                    Text("Albums group photos together.", comment: "Collections explanation")
                }
                .padding(.top, AlohaMetrics.space6)
            }
        }
        .frame(minHeight: collections.isEmpty ? 240 : 0)
    }

    // MARK: - Relationship controls

    private func relationshipControls(_ account: Account) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Button {
                Task { await toggleFollow() }
            } label: {
                if relationship?.following == true {
                    Text("Following", comment: "Profile action")
                } else if relationship?.requested == true {
                    Text("Requested", comment: "Profile action")
                } else {
                    Text("Follow", comment: "Profile action")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Menu {
                if relationship?.following == true {
                    // Nextcloud Social enforces this as a predicate of the
                    // timeline query rather than by filtering a page.
                    Button {
                        Task { await toggleShowBoosts() }
                    } label: {
                        Text(
                            relationship?.showingReblogs == true
                                ? String(localized: "Hide boosts", comment: "Profile action")
                                : String(localized: "Show boosts", comment: "Profile action"))
                    }
                    Button {
                        Task { await toggleNotify() }
                    } label: {
                        Text(
                            relationship?.notifying == true
                                ? String(localized: "Stop notifying me", comment: "Profile action")
                                : String(
                                    localized: "Notify me about posts", comment: "Profile action"))
                    }
                    Button {
                        Task { await toggleEndorse() }
                    } label: {
                        Text(
                            relationship?.endorsed == true
                                ? String(
                                    localized: "Don't feature on my profile",
                                    comment: "Profile action")
                                : String(
                                    localized: "Feature on my profile", comment: "Profile action"))
                    }
                    Divider()
                }

                NavigationLink(
                    value: Route.conversation(
                        Conversation(id: "new-\(account.id)", accounts: [account]))
                ) {
                    Label {
                        Text("Message", comment: "Profile action")
                    } icon: {
                        Image(systemName: AlohaSymbol.envelope)
                    }
                }
                Button {
                    onAction(.addToList(account))
                } label: {
                    Label {
                        Text("Add to list", comment: "Profile action")
                    } icon: {
                        Image(systemName: AlohaSymbol.list)
                    }
                }
                Button {
                    startEditingNote()
                } label: {
                    Label {
                        (relationship?.note ?? "").isEmpty
                            ? Text("Add a note", comment: "Profile action")
                            : Text("Edit note", comment: "Profile action")
                    } icon: {
                        Image(systemName: "note.text")
                    }
                }
                if relationship?.followedBy == true {
                    Button {
                        isConfirmingRemoveFollower = true
                    } label: {
                        Label {
                            Text("Remove from followers", comment: "Profile action")
                        } icon: {
                            Image(systemName: "person.badge.minus")
                        }
                    }
                }
                Divider()

                Button(role: .destructive) {
                    onAction(.mute(account))
                } label: {
                    Text("Mute", comment: "Profile action")
                }
                Button(role: .destructive) {
                    onAction(.block(account))
                } label: {
                    Text("Block", comment: "Profile action")
                }
                if let host = account.host, host != session.snapshot.instanceHost,
                    relationship?.domainBlocking != true
                {
                    Button(role: .destructive) {
                        isConfirmingDomainBlock = true
                    } label: {
                        Text("Block \(host)", comment: "Profile action")
                    }
                }
                Button(role: .destructive) {
                    onAction(.report(Status(id: "", account: account)))
                } label: {
                    Text("Report", comment: "Profile action")
                }
            } label: {
                Image(systemName: AlohaSymbol.more)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(Text("More actions", comment: "Profile action"))
        }
    }

    // MARK: - Loading

    private func load() async {
        do {
            async let accountTask = session.client.decode(
                Account.self, from: Endpoint.accounts.account(accountID))
            async let relationshipsTask = session.client.decode(
                LossyArray<Relationship>.self,
                from: Endpoint.accounts.relationships([accountID]))

            account = try await accountTask
            relationship = try await relationshipsTask.elements.first
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
        await loadExtras()
    }

    /// Every extra is optional and independent, so each fails on its own.
    private func loadExtras() async {
        async let pinnedTask = session.client.decode(
            LossyArray<Status>.self, from: Endpoint.profile.pinnedStatuses(accountID))
        async let featuredTask = session.client.decode(
            LossyArray<FeaturedTag>.self, from: Endpoint.profile.featuredTags(accountID))
        pinned = (try? await pinnedTask)?.elements ?? []
        featuredTags = (try? await featuredTask)?.elements ?? []

        if session.capabilities.isNextcloudSocial {
            highlights = try? await session.client.decode(
                ProfileHighlights.self, from: Endpoint.profile.highlights(accountID))
        }
        if !isOwn {
            familiar =
                (try? await session.client.decode(
                    LossyArray<FamiliarFollowers>.self,
                    from: Endpoint.profile.familiarFollowers([accountID])))?
                .elements.first?.accounts ?? []
        }
        if session.capabilities.stories {
            let live =
                (try? await session.client.decode(
                    LossyArray<Story>.self, from: Endpoint.stories.forAccount(accountID)))?
                .elements ?? []
            stories = live.filter { $0.isLive() }
        }
        if session.capabilities.collections {
            collections =
                (try? await session.client.decode(
                    LossyArray<Collection>.self, from: Endpoint.collections.forAccount(accountID)))?
                .elements ?? []
        }
    }

    private func toggleFollow() async {
        let isFollowing = relationship?.following == true || relationship?.requested == true
        let endpoint =
            isFollowing
            ? Endpoint.accounts.simpleAction(accountID, "unfollow")
            : Endpoint.accounts.follow(accountID)
        await update(with: endpoint)
    }

    private func toggleShowBoosts() async {
        let current = relationship?.showingReblogs ?? true
        await update(with: Endpoint.accounts.follow(accountID, reblogs: !current))
    }

    private func toggleNotify() async {
        let current = relationship?.notifying ?? false
        await update(
            with: Endpoint.accounts.follow(
                accountID, reblogs: relationship?.showingReblogs ?? true, notify: !current))
    }

    private func toggleEndorse() async {
        let current = relationship?.endorsed ?? false
        await update(
            with: current
                ? Endpoint.profile.unendorse(accountID) : Endpoint.profile.endorse(accountID))
    }

    private func startEditingNote() {
        noteDraft = relationship?.note ?? ""
        isEditingNote = true
    }

    private func saveNote() async {
        await update(
            with: Endpoint.profile.setNote(
                accountID, comment: noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private func blockDomain() async {
        guard let host = account?.host else { return }
        do {
            _ = try await session.client.send(Endpoint.accounts.blockDomain(host))
            relationship = try await session.client.decode(
                LossyArray<Relationship>.self,
                from: Endpoint.accounts.relationships([accountID])
            ).elements.first
        } catch {
            await session.handle(error)
        }
    }

    private func update(with endpoint: Endpoint) async {
        do {
            relationship = try await session.client.decode(Relationship.self, from: endpoint)
        } catch {
            await session.handle(error)
        }
    }
}

// MARK: - The tab's posts

/// A timeline drawn inside the profile's own scroll view, so the header
/// scrolls away with the posts instead of pinning them below it.
struct ProfileStatusList: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void
    @State private var model: TimelineModel

    init(key: TimelineKey, session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
        _model = State(initialValue: TimelineModel(key: key, session: session))
    }

    private var statuses: [Status] { model.rows.compactMap(\.status) }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.destructive)
                    .padding(AlohaMetrics.space4)
            }

            ForEach(statuses) { status in
                StatusRow(
                    status: status,
                    policy: session.settings.sensitiveMediaPolicy,
                    localHost: session.snapshot.instanceHost,
                    filterWarning: model.filterWarning(for: status),
                    canReact: session.capabilities.emojiReactions,
                    isOwn: status.displayed.account.id == session.snapshot.serverAccountID,
                    onAction: onAction
                )
                .padding(.horizontal, AlohaMetrics.space4)
                .onAppear {
                    if status.id == statuses.last?.id {
                        Task { await model.loadOlder() }
                    }
                    model.prefetchMedia(around: status.id)
                }
            }

            if model.isRefreshing && statuses.isEmpty {
                ForEach(0..<3, id: \.self) { index in
                    SkeletonRow(hasMedia: index == 1)
                        .padding(.horizontal, AlohaMetrics.space4)
                }
            } else if statuses.isEmpty {
                ContentUnavailableView {
                    Text("Nothing here yet", comment: "Empty profile tab")
                }
                .padding(.top, AlohaMetrics.space6)
            }

            if model.isPagingOlder {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(AlohaMetrics.space3)
            }
        }
        .task { await model.appear() }
        .onChange(of: session.lastPosted?.id) { _, _ in
            guard let posted = session.lastPosted else { return }
            Task { await model.insertOwn(posted) }
        }
    }
}
