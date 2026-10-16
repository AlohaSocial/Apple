// SPDX-License-Identifier: MIT

import Foundation

public struct Status: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var uri: String
    @LenientURL public var url: URL?
    public var createdAt: Date
    public var editedAt: Date?
    /// Restricted HTML. Deliberately left as a `String` here: parsing happens
    /// lazily, off the main actor, cached by content hash (docs/04 §2).
    public var content: String
    public var spoilerText: String
    public var visibility: Visibility
    @LenientBool public var sensitive: Bool
    public var language: String?
    public var account: Account

    @LenientInt public var repliesCount: Int
    @LenientInt public var reblogsCount: Int
    @LenientInt public var favouritesCount: Int

    @LenientBool public var favourited: Bool
    @LenientBool public var reblogged: Bool
    @LenientBool public var bookmarked: Bool
    @LenientBool public var pinned: Bool
    @LenientBool public var muted: Bool

    @FlexibleOptionalID public var inReplyToID: String?
    @FlexibleOptionalID public var inReplyToAccountID: String?

    public var reblog: Box<Status>?
    public var mediaAttachments: [MediaAttachment]
    public var mentions: [Mention]
    public var tags: [StatusTag]
    public var emojis: [CustomEmoji]
    /// Present-or-null on Nextcloud Social, which holds to its own rule that a
    /// client should never have to test for a missing key. Other servers omit it.
    public var poll: Poll?
    public var card: Card?
    public var application: ApplicationSummary?
    public var text: String?
    public var filtered: [FilterResult]?

    /// **Nextcloud Social / Misskey / Pleroma extension.** Emoji reactions to a
    /// status. Mastodon itself does not handle these.
    public var reactions: [Reaction]?
    /// Quote posts, where the server supports them.
    @FlexibleOptionalID public var quoteID: String?
    /// The quoted post itself, when the server embeds it (Mastodon 4.4 shape
    /// `{state, quoted_status}`, or the status directly on other servers).
    public var quote: QuotedStatus?
    /// Who may quote this post: `public`, `followers` or `nobody`. Read from
    /// `quote_approval.automatic` (Mastodon 4.5's shape, which is what the
    /// server sends on its own posts), or from a bare `quote_approval_policy`
    /// where a server sends that. `nil` where the server says nothing.
    public var quoteApprovalPolicy: String?
    /// Mastodon 4.5's `quote_approval`: who is approved, and where the reader
    /// stands. Only a server's own posts carry it.
    public var quoteApproval: QuoteApproval?
    /// What a remote post's server allows — `reply`, `boost`, `like` → allowed
    /// — when it publishes interaction policies. `nil` almost always.
    public var interactionPolicy: [String: Bool]?

    // Nextcloud Social extras. All optional on the wire; absent elsewhere.
    /// PeerTube's thumbs-down, on videos.
    @LenientInt public var dislikesCount: Int
    @LenientBool public var disliked: Bool
    /// Off the profile, not deleted (Pixelfed's notion). `nil` when the server
    /// does not say.
    public var archived: Bool?
    /// Where the post was made, when the author tagged a place.
    public var place: StatusPlace?

    // Aloha Social's own. All `null` or absent elsewhere.
    /// Who may reply, as the server stores it (a comma-joined set); `nil` on
    /// posts from other servers. Read it through `replyAudience`.
    public var replyPolicy: String?
    /// Whether this reply's thread author hid it. `nil` outside a thread.
    public var hiddenByAuthor: Bool?
    /// Whether the reader may hide this reply — they wrote the post it answers.
    public var canHide: Bool?
    /// Where a reply stands with a server that approves replies.
    public var replyApproval: ReplyApproval?
    /// The post says it was made with AI, by a hashtag or by a picture's
    /// metadata. A label the post carries, never a judgement about it.
    @LenientBool public var aiGenerated: Bool
    /// A post read from Bluesky.
    public var bluesky: BlueskyPostReference?
    /// Why the post is on For you; only that feed sends it.
    public var interest: StatusInterest?
    /// How many posts quote this one (Mastodon 4.5). `nil` where the server
    /// says nothing, which is different from none.
    public var quotesCount: Int?
    /// How many people read it. Only the author's own posts carry a value.
    public var viewCount: Int?

    /// A quoted post as the server embeds it.
    public struct QuotedStatus: Codable, Sendable, Hashable {
        /// `accepted`, `pending`, `revoked`, … — or `nil` where the server
        /// sends the status bare.
        public var state: String?
        public var quotedStatus: Box<Status>?

        enum CodingKeys: String, CodingKey {
            case state
            case quotedStatus = "quoted_status"
        }

        public init(state: String? = nil, quotedStatus: Status?) {
            self.state = state
            self.quotedStatus = quotedStatus.map(Box.init)
        }

        public init(from decoder: any Decoder) throws {
            // Either the wrapper or the status itself; both are seen.
            if let c = try? decoder.container(keyedBy: CodingKeys.self),
                c.contains(.quotedStatus) || c.contains(.state)
            {
                state = try c.decodeIfPresent(String.self, forKey: .state)
                quotedStatus = try? c.decodeIfPresent(Box<Status>.self, forKey: .quotedStatus)
            } else {
                state = nil
                quotedStatus = try? Box<Status>(from: decoder)
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(state, forKey: .state)
            try c.encodeIfPresent(quotedStatus, forKey: .quotedStatus)
        }
    }

    /// Mastodon 4.5's `quote_approval` (`Stream::exportQuoteApproval`).
    public struct QuoteApproval: Codable, Sendable, Hashable {
        /// Who may quote without asking: `public`, `followers`; empty for
        /// nobody.
        public var automatic: [String]
        /// Who would have to be asked. Always empty on Aloha Social, which
        /// answers a quote request the moment it arrives.
        public var manual: [String]
        /// `automatic`, `manual`, `denied` or `unknown`, for the reader.
        public var currentUser: String?

        enum CodingKeys: String, CodingKey {
            case automatic, manual
            case currentUser = "current_user"
        }

        public init(automatic: [String] = [], manual: [String] = [], currentUser: String? = nil) {
            self.automatic = automatic
            self.manual = manual
            self.currentUser = currentUser
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            automatic = (try? c.decodeIfPresent([String].self, forKey: .automatic)) ?? []
            manual = (try? c.decodeIfPresent([String].self, forKey: .manual)) ?? []
            currentUser = try? c.decodeIfPresent(String.self, forKey: .currentUser)
        }

        /// The policy the composer and the quote settings speak: the first
        /// automatic audience, or `nobody` when there is none.
        public var policy: String { automatic.first ?? "nobody" }
    }

    /// A place a post was tagged with (Nextcloud Social).
    public struct StatusPlace: Codable, Sendable, Hashable, Identifiable {
        @FlexibleID public var id: String
        public var name: String
        public var country: String?
        public var latitude: Double?
        public var longitude: Double?

        /// The server's Pixelfed shape (`Place::jsonSerialize`): `long`, and
        /// strings rather than numbers. `lon` is read too, for cached rows.
        enum CodingKeys: String, CodingKey {
            case id, name, country
            case latitude = "lat"
            case longitude = "long"
            case legacyLongitude = "lon"
        }

        public init(
            id: String, name: String, country: String? = nil,
            latitude: Double? = nil, longitude: Double? = nil
        ) {
            _id = .init(wrappedValue: id)
            self.name = name
            self.country = country
            self.latitude = latitude
            self.longitude = longitude
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            _id = try c.decode(FlexibleID.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            country = try? c.decodeIfPresent(String.self, forKey: .country)
            latitude = PlaceCoordinate.decode(c, .latitude)
            longitude =
                PlaceCoordinate.decode(c, .longitude)
                ?? PlaceCoordinate.decode(c, .legacyLongitude)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(country, forKey: .country)
            try c.encodeIfPresent(latitude, forKey: .latitude)
            try c.encodeIfPresent(longitude, forKey: .longitude)
        }

        /// "Name, Country", or just the name.
        public var label: String {
            if let country, !country.isEmpty { return "\(name), \(country)" }
            return name
        }
    }

    public struct Mention: Codable, Sendable, Hashable, Identifiable {
        @FlexibleID public var id: String
        public var username: String
        public var acct: String
        @LenientURL public var url: URL?

        public init(id: String, username: String, acct: String, url: URL? = nil) {
            _id = .init(wrappedValue: id)
            self.username = username
            self.acct = acct
            _url = .init(wrappedValue: url)
        }
    }

    public struct StatusTag: Codable, Sendable, Hashable {
        public var name: String
        @LenientURL public var url: URL?

        public init(name: String, url: URL? = nil) {
            self.name = name
            _url = .init(wrappedValue: url)
        }
    }

    public struct Reaction: Codable, Sendable, Hashable {
        public var name: String
        @LenientInt public var count: Int
        @LenientBool public var me: Bool
        @LenientURL public var url: URL?
        @LenientURL public var staticURL: URL?

        enum CodingKeys: String, CodingKey {
            case name, count, me, url
            case staticURL = "static_url"
        }

        public init(
            name: String, count: Int, me: Bool = false, url: URL? = nil, staticURL: URL? = nil
        ) {
            self.name = name
            _count = .init(wrappedValue: count)
            _me = .init(wrappedValue: me)
            _url = .init(wrappedValue: url)
            _staticURL = .init(wrappedValue: staticURL)
        }
    }

    public struct FilterResult: Codable, Sendable, Hashable {
        public var filter: Filter
        public var keywordMatches: [String]?
        public var statusMatches: [String]?

        enum CodingKeys: String, CodingKey {
            case filter
            case keywordMatches = "keyword_matches"
            case statusMatches = "status_matches"
        }
    }

    public struct ApplicationSummary: Codable, Sendable, Hashable {
        public var name: String
        @LenientURL public var website: URL?

        public init(name: String, website: URL? = nil) {
            self.name = name
            _website = .init(wrappedValue: website)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, uri, url, content, visibility, sensitive, language, account, reblog
        case mentions, tags, emojis, poll, card, application, text, filtered
        case favourited, reblogged, bookmarked, pinned, muted, reactions
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case spoilerText = "spoiler_text"
        case repliesCount = "replies_count"
        case reblogsCount = "reblogs_count"
        case favouritesCount = "favourites_count"
        case inReplyToID = "in_reply_to_id"
        case inReplyToAccountID = "in_reply_to_account_id"
        case mediaAttachments = "media_attachments"
        case quoteID = "quote_id"
        case quote
        case quoteApprovalPolicy = "quote_approval_policy"
        case quoteApproval = "quote_approval"
        case interactionPolicy = "interaction_policy"
        case dislikesCount = "dislikes_count"
        case disliked, archived, place
        case replyPolicy = "reply_policy"
        case hiddenByAuthor = "hidden_by_author"
        case canHide = "can_hide"
        case replyApproval = "reply_approval"
        case aiGenerated = "ai_generated"
        case bluesky, interest
        case quotesCount = "quotes_count"
        case viewCount = "view_count"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        uri = try c.decodeIfPresent(String.self, forKey: .uri) ?? ""
        _url = try c.decode(LenientURL.self, forKey: .url)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        spoilerText = try c.decodeIfPresent(String.self, forKey: .spoilerText) ?? ""
        // Visibility fails closed: an unrecognised value is treated as the most
        // restrictive thing it could be, never as public.
        visibility = try c.decodeIfPresent(Visibility.self, forKey: .visibility) ?? .unknownCase
        _sensitive = try c.decode(LenientBool.self, forKey: .sensitive)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        account = try c.decode(Account.self, forKey: .account)
        _repliesCount = try c.decode(LenientInt.self, forKey: .repliesCount)
        _reblogsCount = try c.decode(LenientInt.self, forKey: .reblogsCount)
        _favouritesCount = try c.decode(LenientInt.self, forKey: .favouritesCount)
        _favourited = try c.decode(LenientBool.self, forKey: .favourited)
        _reblogged = try c.decode(LenientBool.self, forKey: .reblogged)
        _bookmarked = try c.decode(LenientBool.self, forKey: .bookmarked)
        _pinned = try c.decode(LenientBool.self, forKey: .pinned)
        _muted = try c.decode(LenientBool.self, forKey: .muted)
        _inReplyToID = try c.decode(FlexibleOptionalID.self, forKey: .inReplyToID)
        _inReplyToAccountID = try c.decode(FlexibleOptionalID.self, forKey: .inReplyToAccountID)
        reblog = try? c.decodeIfPresent(Box<Status>.self, forKey: .reblog)
        mediaAttachments =
            (try? c.decode(LossyArray<MediaAttachment>.self, forKey: .mediaAttachments))?.elements
            ?? []
        mentions = (try? c.decode(LossyArray<Mention>.self, forKey: .mentions))?.elements ?? []
        tags = (try? c.decode(LossyArray<StatusTag>.self, forKey: .tags))?.elements ?? []
        emojis = (try? c.decode(LossyArray<CustomEmoji>.self, forKey: .emojis))?.elements ?? []
        poll = try? c.decodeIfPresent(Poll.self, forKey: .poll)
        card = try? c.decodeIfPresent(Card.self, forKey: .card)
        application = try? c.decodeIfPresent(ApplicationSummary.self, forKey: .application)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        filtered = (try? c.decode(LossyArray<FilterResult>.self, forKey: .filtered))?.elements
        reactions = (try? c.decode(LossyArray<Reaction>.self, forKey: .reactions))?.elements
        _quoteID = try c.decode(FlexibleOptionalID.self, forKey: .quoteID)
        quote = try? c.decodeIfPresent(QuotedStatus.self, forKey: .quote)
        quoteApproval = try? c.decodeIfPresent(QuoteApproval.self, forKey: .quoteApproval)
        quoteApprovalPolicy =
            (try? c.decodeIfPresent(String.self, forKey: .quoteApprovalPolicy))
            ?? quoteApproval?.policy
        interactionPolicy = try? c.decodeIfPresent([String: Bool].self, forKey: .interactionPolicy)
        _dislikesCount = try c.decode(LenientInt.self, forKey: .dislikesCount)
        _disliked = try c.decode(LenientBool.self, forKey: .disliked)
        archived = (try? c.decodeIfPresent(LenientBool.self, forKey: .archived))?.wrappedValue
        place = try? c.decodeIfPresent(StatusPlace.self, forKey: .place)
        replyPolicy = try? c.decodeIfPresent(String.self, forKey: .replyPolicy)
        hiddenByAuthor =
            (try? c.decodeIfPresent(LenientBool.self, forKey: .hiddenByAuthor))?.wrappedValue
        canHide = (try? c.decodeIfPresent(LenientBool.self, forKey: .canHide))?.wrappedValue
        replyApproval = try? c.decodeIfPresent(ReplyApproval.self, forKey: .replyApproval)
        _aiGenerated = try c.decode(LenientBool.self, forKey: .aiGenerated)
        bluesky = try? c.decodeIfPresent(BlueskyPostReference.self, forKey: .bluesky)
        interest = try? c.decodeIfPresent(StatusInterest.self, forKey: .interest)
        quotesCount = (try? c.decodeIfPresent(LenientInt.self, forKey: .quotesCount))?.wrappedValue
        viewCount = (try? c.decodeIfPresent(LenientInt.self, forKey: .viewCount))?.wrappedValue
    }

    public init(
        id: String, uri: String = "", url: URL? = nil, createdAt: Date = Date(),
        editedAt: Date? = nil, content: String = "", spoilerText: String = "",
        visibility: Visibility = .public, sensitive: Bool = false, language: String? = nil,
        account: Account, repliesCount: Int = 0, reblogsCount: Int = 0, favouritesCount: Int = 0,
        favourited: Bool = false, reblogged: Bool = false, bookmarked: Bool = false,
        pinned: Bool = false, muted: Bool = false, inReplyToID: String? = nil,
        inReplyToAccountID: String? = nil, reblog: Box<Status>? = nil,
        mediaAttachments: [MediaAttachment] = [], mentions: [Mention] = [],
        tags: [StatusTag] = [], emojis: [CustomEmoji] = [], poll: Poll? = nil,
        card: Card? = nil, application: ApplicationSummary? = nil, text: String? = nil,
        filtered: [FilterResult]? = nil, reactions: [Reaction]? = nil, quoteID: String? = nil,
        quote: QuotedStatus? = nil, quoteApprovalPolicy: String? = nil,
        quoteApproval: QuoteApproval? = nil, interactionPolicy: [String: Bool]? = nil,
        dislikesCount: Int = 0, disliked: Bool = false, archived: Bool? = nil,
        place: StatusPlace? = nil, replyPolicy: String? = nil, hiddenByAuthor: Bool? = nil,
        canHide: Bool? = nil, replyApproval: ReplyApproval? = nil, aiGenerated: Bool = false,
        bluesky: BlueskyPostReference? = nil, interest: StatusInterest? = nil,
        quotesCount: Int? = nil, viewCount: Int? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.uri = uri
        _url = .init(wrappedValue: url)
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.content = content
        self.spoilerText = spoilerText
        self.visibility = visibility
        _sensitive = .init(wrappedValue: sensitive)
        self.language = language
        self.account = account
        _repliesCount = .init(wrappedValue: repliesCount)
        _reblogsCount = .init(wrappedValue: reblogsCount)
        _favouritesCount = .init(wrappedValue: favouritesCount)
        _favourited = .init(wrappedValue: favourited)
        _reblogged = .init(wrappedValue: reblogged)
        _bookmarked = .init(wrappedValue: bookmarked)
        _pinned = .init(wrappedValue: pinned)
        _muted = .init(wrappedValue: muted)
        _inReplyToID = .init(wrappedValue: inReplyToID)
        _inReplyToAccountID = .init(wrappedValue: inReplyToAccountID)
        self.reblog = reblog
        self.mediaAttachments = mediaAttachments
        self.mentions = mentions
        self.tags = tags
        self.emojis = emojis
        self.poll = poll
        self.card = card
        self.application = application
        self.text = text
        self.filtered = filtered
        self.reactions = reactions
        _quoteID = .init(wrappedValue: quoteID)
        self.quote = quote
        self.quoteApprovalPolicy = quoteApprovalPolicy ?? quoteApproval?.policy
        self.quoteApproval = quoteApproval
        self.interactionPolicy = interactionPolicy
        _dislikesCount = .init(wrappedValue: dislikesCount)
        _disliked = .init(wrappedValue: disliked)
        self.archived = archived
        self.place = place
        self.replyPolicy = replyPolicy
        self.hiddenByAuthor = hiddenByAuthor
        self.canHide = canHide
        self.replyApproval = replyApproval
        _aiGenerated = .init(wrappedValue: aiGenerated)
        self.bluesky = bluesky
        self.interest = interest
        self.quotesCount = quotesCount
        self.viewCount = viewCount
    }
}

extension Status {
    /// The status whose content is actually drawn. For a boost that is the
    /// boosted post; the wrapper only contributes the context line.
    public var displayed: Status { reblog?.value ?? self }

    public var isBoost: Bool { reblog != nil }

    /// The account that boosted, when this row is a boost. `nil` otherwise.
    public var booster: Account? { isBoost ? account : nil }

    public var hasContentWarning: Bool {
        !spoilerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var isEdited: Bool { editedAt != nil }

    /// Who may reply, where the server says and this app can draw it.
    public var replyAudience: ReplyPolicy? { ReplyPolicy(wire: replyPolicy) }

    /// A reply the thread's author put away. Shown collapsed, never removed.
    public var isHiddenByAuthor: Bool { hiddenByAuthor == true }

    /// The quoted post, when the server embedded it.
    public var quotedStatus: Status? { quote?.quotedStatus?.value }

    /// Whether the reader may quote this post, where the server says:
    /// `quote_approval.current_user` is `denied` when the policy shuts them
    /// out, and a quote they post anyway would only ever stay pending. `nil`
    /// where nothing was said, which leaves the action as it was.
    public var viewerMayQuote: Bool? {
        switch quoteApproval?.currentUser {
        case "automatic", "manual": true
        case "denied": false
        default: nil
        }
    }

    /// Whether a remote post's server lets the reader do one thing —
    /// `reply`, `boost` or `like` — where it says. `nil` where it does not.
    public func interactionAllowed(_ interaction: String) -> Bool? {
        interactionPolicy?[interaction]
    }

    /// Whether the viewer is the author of the drawn post.
    public func isOwn(viewerAccountID: String) -> Bool {
        displayed.account.id == viewerAccountID
    }

    public var hasMedia: Bool { !mediaAttachments.isEmpty }

    /// True when at least one attachment carries no alt text. Drives the
    /// pre-post warning in the composer (docs/07 §4).
    public var hasUndescribedMedia: Bool {
        mediaAttachments.contains { !$0.hasAltText }
    }

    /// A reply can never be less restrictive than what it answers (docs/07 §3).
    public func replyVisibility(default fallback: Visibility) -> Visibility {
        Visibility.mostRestrictive(fallback, displayed.visibility)
    }

    /// Everyone a reply should address, the author first, minus the replier.
    public func replyMentions(excluding viewerAcct: String?) -> [String] {
        let target = displayed
        var handles: [String] = [target.account.acct]
        handles.append(contentsOf: target.mentions.map(\.acct))
        var seen = Set<String>()
        return handles.filter { handle in
            guard handle != viewerAcct, !handle.isEmpty else { return false }
            return seen.insert(handle).inserted
        }
    }

    /// A reply written somewhere with no composer — dictated on the watch, or
    /// typed into a notification — addressed the way the composer would have
    /// addressed it: every handle the composer would have prefilled, unless
    /// the person already wrote it themselves.
    public func replyText(_ typed: String, excluding viewerAcct: String?) -> String {
        let body = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        // Sentence punctuation only: "@ana," still names @ana, while an
        // underscore or a dot can be part of a handle.
        let sentencePunctuation = CharacterSet(charactersIn: ",.;:!?()\"'“”‘’")
        let written = Set(
            body.split(whereSeparator: \.isWhitespace).map {
                $0.trimmingCharacters(in: sentencePunctuation).lowercased()
            })
        let missing = replyMentions(excluding: viewerAcct).filter {
            !written.contains("@\($0)".lowercased())
        }
        guard !missing.isEmpty else { return body }
        return (missing.map { "@\($0)" } + [body]).joined(separator: " ")
    }
}
