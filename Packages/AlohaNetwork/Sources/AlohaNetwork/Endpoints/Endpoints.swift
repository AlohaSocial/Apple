// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

extension Endpoint {
    public static let defaultLimit = 20
    /// The server caps at 50 whatever is asked for.
    public static let maximumLimit = 50

    static func clampedLimit(_ limit: Int) -> Int {
        min(max(1, limit), maximumLimit)
    }

    static func pageItems(limit: Int, anchor: PageAnchor) -> [URLQueryItem] {
        [URLQueryItem(name: "limit", value: String(clampedLimit(limit)))] + anchor.queryItems
    }
}

// MARK: - Instance

extension Endpoint {
    public enum instance {
        public static var v2: Endpoint {
            Endpoint(path: "api/v2/instance", requiresAuthentication: false)
        }
        public static var v1: Endpoint {
            Endpoint(path: "api/v1/instance/", requiresAuthentication: false)
        }
        public static var rules: Endpoint {
            Endpoint(path: "api/v1/instance/rules", requiresAuthentication: false)
        }
        public static var extendedDescription: Endpoint {
            Endpoint(path: "api/v1/instance/extended_description", requiresAuthentication: false)
        }
        /// 404 where the administrator has published none — the row is then
        /// hidden, not shown broken (docs/05 §9).
        public static var privacyPolicy: Endpoint {
            Endpoint(path: "api/v1/instance/privacy_policy", requiresAuthentication: false)
        }
        public static var termsOfService: Endpoint {
            Endpoint(path: "api/v1/instance/terms_of_service", requiresAuthentication: false)
        }
        public static var translationLanguages: Endpoint {
            Endpoint(path: "api/v1/instance/translation_languages", requiresAuthentication: false)
        }
        public static var customEmojis: Endpoint {
            Endpoint(path: "api/v1/custom_emojis", requiresAuthentication: false)
        }
        /// Every instance this one has heard of, as bare hostnames. Public,
        /// as Mastodon's is: it says who the server federates with, not who
        /// its people are.
        public static var peers: Endpoint {
            Endpoint(path: "api/v1/instance/peers", requiresAuthentication: false)
        }
        /// Twelve weeks of statuses. `logins` and `registrations` are always
        /// zero here — an account is a Nextcloud user, so there is no
        /// registration for the app to count.
        public static var activity: Endpoint {
            Endpoint(path: "api/v1/instance/activity", requiresAuthentication: false)
        }
        /// The servers this one refuses, where the administrator has chosen to
        /// publish the list. Empty otherwise, which is not an error.
        public static var domainBlocks: Endpoint {
            Endpoint(path: "api/v1/instance/domain_blocks", requiresAuthentication: false)
        }
        public static var preferences: Endpoint {
            Endpoint(path: "api/v1/preferences")
        }
        /// **Nextcloud extension.** `''` puts the account back to following the
        /// instance, which is different from picking today's default.
        public static func setExpandMedia(_ policy: String) -> Endpoint {
            Endpoint(
                method: .put, path: "api/v1/preferences",
                body: .form([URLQueryItem(name: "expandMedia", value: policy)]))
        }
    }
}

// MARK: - Session

extension Endpoint {
    public enum session {
        public static var verifyCredentials: Endpoint {
            Endpoint(path: "api/v1/accounts/verify_credentials")
        }
        public static var verifyApplication: Endpoint {
            Endpoint(path: "api/v1/apps/verify_credentials")
        }
    }
}

// MARK: - Timelines

extension Endpoint {
    public enum timelines {
        /// The three narrowings beyond Mastodon's parameters are Nextcloud
        /// Social's own. `only_video` is the narrower of the first two and wins
        /// when both are sent, since every video is media (docs/02 §2).
        public static func timeline(
            _ source: TimelineSource,
            filters: TimelineFilters = .none,
            limit: Int = defaultLimit,
            anchor: PageAnchor = .cold
        ) -> Endpoint {
            var items = pageItems(limit: limit, anchor: anchor)
            items += .flag("local", source.isLocalOnly)
            items += filterItems(filters)

            switch source {
            case .list(let id):
                return Endpoint(path: "api/v1/timelines/list/\(id)", query: items)
            case .hashtag(let name):
                let tag = Tag.normalise(name) ?? name
                return Endpoint(
                    path: "api/v1/timelines/tag/\(tag)", query: items, requiresAuthentication: false
                )
            case .bookmarks:
                return Endpoint(path: "api/v1/bookmarks", query: items)
            case .favourites:
                return Endpoint(path: "api/v1/favourites/", query: items)
            case .account(let id, let includeReplies, let onlyMedia):
                var accountItems = pageItems(limit: limit, anchor: anchor)
                accountItems += .flag("exclude_replies", !includeReplies)
                accountItems += .flag("only_media", onlyMedia)
                return Endpoint(path: "api/v1/accounts/\(id)/statuses", query: accountItems)
            case .trending:
                return Endpoint(
                    path: "api/v1/trends/statuses", query: items, requiresAuthentication: false)
            default:
                let segment = source.pathSegment ?? "home"
                return Endpoint(
                    path: "api/v1/timelines/\(segment)/", query: items,
                    requiresAuthentication: source.requiresViewer)
            }
        }

        private static func filterItems(_ filters: TimelineFilters) -> [URLQueryItem] {
            if filters.onlyVideo { return [URLQueryItem(name: "only_video", value: "true")] }
            var items: [URLQueryItem] = []
            items += .flag("only_media", filters.onlyMedia)
            items += .flag("only_news", filters.onlyNews)
            return items
        }

        public static func conversations(
            limit: Int = defaultLimit, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(path: "api/v1/conversations", query: pageItems(limit: limit, anchor: anchor))
        }

        public static func markConversationRead(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/conversations/\(id)/read")
        }

        /// Marks every conversation read, and answers with how many changed.
        public static var markAllConversationsRead: Endpoint {
            Endpoint(method: .post, path: "api/v1/conversations/read_all")
        }

        /// Takes the conversation off the list. The messages themselves are
        /// not deleted, here or there, and a later message brings it back.
        public static func deleteConversation(_ id: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/conversations/\(id)")
        }

        /// How many conversations have something unread in them.
        public static var conversationsUnreadCount: Endpoint {
            Endpoint(path: "api/v1/conversations/unread_count")
        }

        /// The people a direct message can be started with: mutual follows,
        /// which is who Pixelfed's own composer offers.
        ///
        /// A better opening than a search field — most messages go to somebody
        /// already followed, and searching for them first is a step that
        /// answers a question the app could have answered itself.
        ///
        /// The rest of Pixelfed's `direct/thread` family is deliberately not
        /// wired: `GET /thread`, `POST /thread/send` and
        /// `DELETE /thread/message` are a second representation of the same
        /// direct statuses this screen already reads, writes and deletes
        /// through Mastodon's own routes. Two code paths over one set of posts
        /// is how the two drift.
        public static var directMessageMutuals: Endpoint {
            Endpoint(path: "api/v1.1/direct/compose/mutuals")
        }
    }
}

// MARK: - Statuses

extension Endpoint {
    public enum statuses {
        public static func status(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/statuses/\(id)", requiresAuthentication: false)
        }
        /// The link preview of one status, on its own.
        ///
        /// The card is inlined in the status entity, which is what every list
        /// reads. This route is for the one case that is not covered: a status
        /// whose card the server had not built when it was written. Asking
        /// makes the server build and cache it (`StreamService::attachCard`),
        /// so it is a **detail-screen** request and never a per-row one — a
        /// timeline that asked for each row would be a request storm for a
        /// decoration. A status with no link answers `{}`, which is Mastodon's
        /// answer too and not an error.
        public static func card(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/statuses/\(id)/card", requiresAuthentication: false)
        }

        public static func context(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/statuses/\(id)/context", requiresAuthentication: false)
        }
        public static func history(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/statuses/\(id)/history", requiresAuthentication: false)
        }
        /// The original plain text. An edit composer must load this, never the
        /// rendered HTML (docs/07 §8).
        public static func source(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/statuses/\(id)/source")
        }
        public static func favouritedBy(_ id: String, limit: Int = defaultLimit) -> Endpoint {
            Endpoint(
                path: "api/v1/statuses/\(id)/favourited_by",
                query: pageItems(limit: limit, anchor: .cold))
        }
        public static func rebloggedBy(_ id: String, limit: Int = defaultLimit) -> Endpoint {
            Endpoint(
                path: "api/v1/statuses/\(id)/reblogged_by",
                query: pageItems(limit: limit, anchor: .cold))
        }
        public static func action(_ id: String, _ action: StatusAction) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/statuses/\(id)/\(action.rawValue)")
        }
        public static func delete(_ id: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/statuses/\(id)")
        }
        public static func translate(_ id: String, to language: String?) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/statuses/\(id)/translate",
                body: .form(.optional("lang", language)))
        }
        public static func react(_ id: String, emoji: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/statuses/\(id)/react",
                body: .form([
                    URLQueryItem(name: "name", value: emoji)
                ]))
        }
        public static func unreact(_ id: String, emoji: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/statuses/\(id)/unreact",
                body: .form([
                    URLQueryItem(name: "name", value: emoji)
                ]))
        }
        public static func vote(pollID: String, choices: [Int]) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/polls/\(pollID)/votes",
                body: .form(.repeated("choices", choices.map(String.init))))
        }
    }

    public enum StatusAction: String, Sendable {
        case favourite, unfavourite, reblog, unreblog, bookmark, unbookmark
        case pin, unpin, mute, unmute
    }
}

// MARK: - Accounts

extension Endpoint {
    public enum accounts {
        public static func account(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/accounts/\(id)", requiresAuthentication: false)
        }
        public static func relationships(_ ids: [String]) -> Endpoint {
            Endpoint(path: "api/v1/accounts/relationships", query: .repeated("id", ids))
        }
        public static var followRequests: Endpoint {
            Endpoint(path: "api/v1/follow_requests")
        }
        public static func authoriseFollowRequest(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/follow_requests/\(id)/authorize")
        }
        public static func rejectFollowRequest(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/follow_requests/\(id)/reject")
        }
        public static func lookup(acct: String) -> Endpoint {
            Endpoint(
                path: "api/v1/accounts/lookup",
                query: [URLQueryItem(name: "acct", value: acct)], requiresAuthentication: false)
        }
        /// What a composer calls to complete a `@handle`. No client substitutes
        /// `/api/v2/search` for it, and Nextcloud Social serves it precisely
        /// because a composer needs it (docs/07 §2).
        public static func search(
            _ query: String, limit: Int = 8, resolve: Bool = false
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/accounts/search",
                query: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "limit", value: String(limit)),
                ] + .flag("resolve", resolve))
        }
        public static func follow(
            _ id: String, reblogs: Bool = true, notify: Bool = false
        ) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/accounts/\(id)/follow",
                body: .form([
                    URLQueryItem(name: "reblogs", value: reblogs ? "true" : "false"),
                    URLQueryItem(name: "notify", value: notify ? "true" : "false"),
                ]))
        }
        public static func simpleAction(_ id: String, _ action: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/accounts/\(id)/\(action)")
        }
        public static func mute(_ id: String, notifications: Bool, duration: Int?) -> Endpoint {
            var items = [
                URLQueryItem(name: "notifications", value: notifications ? "true" : "false")
            ]
            if let duration {
                items.append(URLQueryItem(name: "duration", value: String(duration)))
            }
            return Endpoint(method: .post, path: "api/v1/accounts/\(id)/mute", body: .form(items))
        }
        public static func followers(
            _ id: String, limit: Int = defaultLimit, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/accounts/\(id)/followers",
                query: pageItems(limit: limit, anchor: anchor))
        }
        public static func following(
            _ id: String, limit: Int = defaultLimit, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/accounts/\(id)/following",
                query: pageItems(limit: limit, anchor: anchor))
        }
        /// Sends no `Link` header and takes no cursor — paged by `limit` alone
        /// in a bounded loop (docs/11 §1.3).
        public static func blocks(limit: Int = 40) -> Endpoint {
            Endpoint(
                path: "api/v1/blocks", query: [URLQueryItem(name: "limit", value: String(limit))])
        }
        public static func mutes(limit: Int = 40) -> Endpoint {
            Endpoint(
                path: "api/v1/mutes", query: [URLQueryItem(name: "limit", value: String(limit))])
        }
        public static var domainBlocks: Endpoint { Endpoint(path: "api/v1/domain_blocks") }
        public static func blockDomain(_ domain: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/domain_blocks",
                body: .form([
                    URLQueryItem(name: "domain", value: domain)
                ]))
        }
        public static func unblockDomain(_ domain: String) -> Endpoint {
            Endpoint(
                method: .delete, path: "api/v1/domain_blocks",
                body: .form([
                    URLQueryItem(name: "domain", value: domain)
                ]))
        }
    }
}

// MARK: - Notifications

extension Endpoint {
    public enum notifications {
        public static func grouped(
            limit: Int = 40, anchor: PageAnchor = .cold,
            types: [String] = [], excludeTypes: [String] = []
        ) -> Endpoint {
            Endpoint(
                path: "api/v2/notifications",
                query: pageItems(limit: limit, anchor: anchor)
                    + .repeated("types", types) + .repeated("exclude_types", excludeTypes))
        }
        public static func flat(
            limit: Int = defaultLimit, anchor: PageAnchor = .cold,
            types: [String] = [], excludeTypes: [String] = []
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/notifications",
                query: pageItems(limit: limit, anchor: anchor)
                    + .repeated("types", types) + .repeated("exclude_types", excludeTypes))
        }
        public static func unreadCount(grouped: Bool) -> Endpoint {
            Endpoint(
                path: grouped
                    ? "api/v2/notifications/unread_count" : "api/v1/notifications/unread_count")
        }
        public static func groupAccounts(_ key: String) -> Endpoint {
            Endpoint(path: "api/v2/notifications/\(key)/accounts")
        }
        public static func dismissGroup(_ key: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v2/notifications/\(key)/dismiss")
        }
        public static func dismiss(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/notifications/\(id)/dismiss")
        }
        public static var clear: Endpoint {
            Endpoint(method: .post, path: "api/v1/notifications/clear")
        }
        /// v2 is where a 4.3 client looks and the only place it looks; the v1
        /// spelling stays for clients written against 4.2.
        public static func policy(v2: Bool) -> Endpoint {
            Endpoint(path: v2 ? "api/v2/notifications/policy" : "api/v1/notifications/policy")
        }
        public static var requests: Endpoint {
            Endpoint(
                path: "api/v1/notifications/requests",
                query: [
                    URLQueryItem(name: "limit", value: "40")
                ])
        }
        public static func acceptRequest(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/notifications/requests/\(id)/accept")
        }
        public static func dismissRequest(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/notifications/requests/\(id)/dismiss")
        }
    }

    public enum markers {
        public static var read: Endpoint {
            Endpoint(
                path: "api/v1/markers",
                query: .repeated("timeline", ["home", "notifications"]))
        }
        /// A marker never moves backwards: the server enforces it and so does
        /// the caller, so a device that is behind cannot un-read what another
        /// has read (docs/08 §7).
        public static func write(home: String?, notifications: String?) -> Endpoint {
            var items: [URLQueryItem] = []
            if let home { items.append(URLQueryItem(name: "home[last_read_id]", value: home)) }
            if let notifications {
                items.append(
                    URLQueryItem(name: "notifications[last_read_id]", value: notifications))
            }
            return Endpoint(method: .post, path: "api/v1/markers", body: .form(items))
        }
    }
}

// MARK: - Search, tags, lists, filters

extension Endpoint {
    public enum search {
        public static func search(
            _ query: String, type: String? = nil, resolve: Bool = false, limit: Int = defaultLimit
        ) -> Endpoint {
            Endpoint(
                path: "api/v2/search",
                query: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "limit", value: String(clampedLimit(limit))),
                ] + .optional("type", type) + .flag("resolve", resolve))
        }
        /// The instance's own profile directory: the accounts here that chose
        /// to be discoverable, most recently active first.
        ///
        /// `local` is accepted by the server and ignored — only accounts it
        /// holds the profile of carry the flag, and publishing a directory of
        /// cached remote actors would be this instance listing somebody else's
        /// users — so it is not sent.
        public static func directory(
            order: DirectoryOrder = .active, limit: Int = 40, offset: Int = 0
        ) -> Endpoint {
            Endpoint(
                path: "api/v1/directory",
                query: [
                    URLQueryItem(name: "order", value: order.rawValue),
                    URLQueryItem(name: "limit", value: String(clampedLimit(limit))),
                    URLQueryItem(name: "offset", value: String(max(0, offset))),
                ],
                requiresAuthentication: false)
        }

        public enum DirectoryOrder: String, Sendable, Hashable, CaseIterable, Identifiable {
            /// Most recently posted.
            case active
            /// Most recently joined.
            case new
            public var id: String { rawValue }
        }

        public static func trendingTags(limit: Int = 10, period: String = "1d") -> Endpoint {
            Endpoint(
                path: "api/v1/trends/tags",
                query: [
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "period", value: period),
                ], requiresAuthentication: false)
        }
        public static func trendingLinks(limit: Int = 10) -> Endpoint {
            Endpoint(
                path: "api/v1/trends/links",
                query: [URLQueryItem(name: "limit", value: String(limit))],
                requiresAuthentication: false)
        }
        public static var suggestions: Endpoint {
            Endpoint(path: "api/v2/suggestions", query: [URLQueryItem(name: "limit", value: "20")])
        }
        public static func dismissSuggestion(_ id: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/suggestions/\(id)")
        }
    }

    public enum tags {
        public static func tag(_ name: String) -> Endpoint {
            Endpoint(path: "api/v1/tags/\(Tag.normalise(name) ?? name)")
        }
        public static func follow(_ name: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/tags/\(Tag.normalise(name) ?? name)/follow")
        }
        public static func unfollow(_ name: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/tags/\(Tag.normalise(name) ?? name)/unfollow")
        }
        /// Pages on the followed-tag row id, not a status id: a tag can be
        /// unfollowed and followed again, so its name does not move in one
        /// direction and cannot page (docs/02 §5).
        public static func followed(
            limit: Int = defaultLimit, anchor: PageAnchor = .cold
        ) -> Endpoint {
            Endpoint(path: "api/v1/followed_tags", query: pageItems(limit: limit, anchor: anchor))
        }
    }

    public enum lists {
        public static var all: Endpoint { Endpoint(path: "api/v1/lists") }
        public static func create(title: String) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/lists",
                body: .form([
                    URLQueryItem(name: "title", value: title)
                ]))
        }
        public static func delete(_ id: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/lists/\(id)")
        }
        public static func accounts(_ id: String) -> Endpoint {
            Endpoint(
                path: "api/v1/lists/\(id)/accounts",
                query: [
                    URLQueryItem(name: "limit", value: "0")
                ])
        }
    }

    public enum filters {
        public static var all: Endpoint { Endpoint(path: "api/v2/filters") }

        public static func get(_ id: String) -> Endpoint {
            Endpoint(path: "api/v2/filters/\(id)")
        }

        public static func delete(_ id: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v2/filters/\(id)")
        }

        /// Creates a filter with the words it starts with.
        ///
        /// `keywords_attributes[n][…]` is Rails' nested-attributes shape, and
        /// it is what Mastodon's v2 API takes — a flat `keywords[]` is
        /// silently ignored by both servers.
        public static func create(
            title: String, context: [FilterContext], action: FilterAction,
            expiresIn: TimeInterval?, keywords: [KeywordDraft]
        ) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v2/filters",
                body: .form(
                    [URLQueryItem(name: "title", value: title)]
                        + contextItems(context)
                        + [URLQueryItem(name: "filter_action", value: action.rawValue)]
                        + expiryItems(expiresIn)
                        + keywordItems(keywords)))
        }

        /// Changes a filter. What is not named is left alone by the server, so
        /// only what the editor touched is sent.
        public static func update(
            _ id: String, title: String, context: [FilterContext], action: FilterAction,
            expiresIn: TimeInterval?, keywords: [KeywordDraft]
        ) -> Endpoint {
            Endpoint(
                method: .put, path: "api/v2/filters/\(id)",
                body: .form(
                    [URLQueryItem(name: "title", value: title)]
                        + contextItems(context)
                        + [URLQueryItem(name: "filter_action", value: action.rawValue)]
                        + expiryItems(expiresIn)
                        + keywordItems(keywords)))
        }

        /// One word of a filter as the editor holds it: an existing keyword
        /// carries its id, a new one does not, and one the editor removed is
        /// sent with `_destroy` so the server drops it.
        public struct KeywordDraft: Sendable, Hashable, Identifiable {
            public var id: String?
            public var keyword: String
            public var wholeWord: Bool
            public var destroy: Bool

            public init(
                id: String? = nil, keyword: String, wholeWord: Bool = false, destroy: Bool = false
            ) {
                self.id = id
                self.keyword = keyword
                self.wholeWord = wholeWord
                self.destroy = destroy
            }
        }

        private static func contextItems(_ context: [FilterContext]) -> [URLQueryItem] {
            context.filter { !$0.isUnknown }.map {
                URLQueryItem(name: "context[]", value: $0.rawValue)
            }
        }

        /// An absent expiry has to be sent as `''` rather than omitted: the
        /// server leaves an unnamed field alone, so omitting it on an update
        /// would keep an expiry the editor has just cleared.
        private static func expiryItems(_ expiresIn: TimeInterval?) -> [URLQueryItem] {
            [
                URLQueryItem(
                    name: "expires_in",
                    value: expiresIn.map { String(Int($0.rounded())) } ?? "")
            ]
        }

        private static func keywordItems(_ keywords: [KeywordDraft]) -> [URLQueryItem] {
            keywords.enumerated().flatMap { index, draft -> [URLQueryItem] in
                let prefix = "keywords_attributes[\(index)]"
                var items: [URLQueryItem] = [
                    URLQueryItem(name: "\(prefix)[keyword]", value: draft.keyword),
                    URLQueryItem(name: "\(prefix)[whole_word]", value: draft.wholeWord ? "1" : "0"),
                ]
                if let id = draft.id {
                    items.append(URLQueryItem(name: "\(prefix)[id]", value: id))
                }
                if draft.destroy {
                    items.append(URLQueryItem(name: "\(prefix)[_destroy]", value: "1"))
                }
                return items
            }
        }
    }
}

// MARK: - Media, composing, Nextcloud extensions

extension Endpoint {
    public enum media {
        /// Modern clients POST v2 and only fall back to v1 on a 404.
        public static func upload(
            data: Data, filename: String, mimeType: String, description: String?, v2: Bool = true
        ) -> Endpoint {
            var parts: [Multipart.Part] = [
                .init(name: "file", filename: filename, mimeType: mimeType, data: data)
            ]
            if let description, !description.isEmpty {
                parts.append(.field("description", description))
            }
            return Endpoint(
                method: .post, path: v2 ? "api/v2/media" : "api/v1/media",
                body: .multipart(Multipart(parts: parts)))
        }

        public static func updateDescription(_ id: String, description: String) -> Endpoint {
            Endpoint(
                method: .put, path: "api/v1/media/\(id)",
                body: .form([
                    URLQueryItem(name: "description", value: description)
                ]))
        }

        /// **Nextcloud extension.** Attaches a file the viewer already has,
        /// so a picture on the server never travels to the phone and back.
        /// A traversal or a folder is a 422 (docs/07 §6).
        public static func fromNextcloudFile(path: String, description: String?) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/media/from-file",
                body: .form(
                    [URLQueryItem(name: "path", value: path)]
                        + .optional("description", description)))
        }
    }

    public enum composing {
        public static func post(_ draft: StatusPost) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/statuses", body: .form(draft.formItems),
                idempotencyKey: draft.idempotencyKey)
        }
        public static func edit(_ id: String, _ draft: StatusPost) -> Endpoint {
            Endpoint(method: .put, path: "api/v1/statuses/\(id)", body: .form(draft.formItems))
        }
        public static var scheduled: Endpoint { Endpoint(path: "api/v1/scheduled_statuses") }
        public static func deleteScheduled(_ id: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/scheduled_statuses/\(id)")
        }
    }

    /// Nextcloud Social's own video surface.
    public enum video {
        /// Never federated, never shown to anybody else, never counted into
        /// anything. One row per (post, viewer).
        public static func reportWatched(
            _ statusID: String, position: Double, duration: Double
        ) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/statuses/\(statusID)/watched",
                body: .form([
                    URLQueryItem(name: "position", value: String(Int(position))),
                    URLQueryItem(name: "duration", value: String(Int(duration))),
                ]))
        }
        public static func forgetWatched(_ statusID: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/statuses/\(statusID)/watched")
        }
        public static func continueWatching(limit: Int = 20) -> Endpoint {
            Endpoint(
                path: "api/v1/videos/continue",
                query: [URLQueryItem(name: "limit", value: String(min(limit, 40)))])
        }
    }

    public enum stories {
        public static var carousel: Endpoint { Endpoint(path: "api/v1/stories/carousel") }
        public static var own: Endpoint { Endpoint(path: "api/v1/stories/self") }
        public static func forAccount(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/accounts/\(id)/stories")
        }
        public static func post(mediaID: String, caption: String?, duration: Int) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/stories",
                body: .form(
                    [
                        URLQueryItem(name: "media_id", value: mediaID),
                        // The server clamps to 3–30 anyway; clamping here keeps the UI
                        // from offering something that will be silently changed.
                        URLQueryItem(name: "duration", value: String(min(max(duration, 3), 30))),
                    ] + .optional("caption", caption.map { String($0.prefix(500)) })))
        }
        public static func markSeen(_ id: String) -> Endpoint {
            Endpoint(method: .post, path: "api/v1/stories/\(id)/seen")
        }
        public static func delete(_ id: String) -> Endpoint {
            Endpoint(method: .delete, path: "api/v1/stories/\(id)")
        }
    }

    public enum collections {
        public static var all: Endpoint { Endpoint(path: "api/v1/collections") }
        public static func forAccount(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/accounts/\(id)/collections")
        }
        public static func items(_ id: String) -> Endpoint {
            Endpoint(path: "api/v1/collections/\(id)/items")
        }
    }

    public enum safety {
        public static func report(
            accountID: String, statusIDs: [String], comment: String,
            forward: Bool, category: String, ruleIDs: [String]
        ) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/reports",
                body: .form(
                    [
                        URLQueryItem(name: "account_id", value: accountID),
                        URLQueryItem(name: "comment", value: comment),
                        URLQueryItem(name: "forward", value: forward ? "true" : "false"),
                        URLQueryItem(name: "category", value: category),
                    ] + .repeated("status_ids", statusIDs) + .repeated("rule_ids", ruleIDs)))
        }
        public static var announcements: Endpoint { Endpoint(path: "api/v1/announcements") }
    }
}

/// What the composer sends. Kept here so the form encoding lives beside the
/// endpoint that uses it.
public struct StatusPost: Sendable, Hashable {
    public var text: String
    public var visibility: Visibility
    public var spoilerText: String?
    public var sensitive: Bool
    public var language: String?
    public var inReplyToID: String?
    public var mediaIDs: [String]
    public var pollOptions: [String]
    public var pollExpiresIn: Int?
    public var pollMultiple: Bool
    public var pollHideTotals: Bool
    public var scheduledAt: Date?
    /// Generated when the composer opened and regenerated only when content
    /// changes. This is what makes retry-on-timeout safe (docs/07 §5).
    public var idempotencyKey: String

    // Nextcloud Social extras. All optional; a stock server ignores them.
    /// The post being quoted.
    public var quotedID: String?
    /// Who may quote the new post: `public`, `followers` or `nobody`.
    public var quotePolicy: String?
    /// A place the server already knows.
    public var placeID: String?
    /// A place it does not: name and country make one.
    public var placeName: String?
    public var placeCountry: String?
    public var placeLatitude: Double?
    public var placeLongitude: Double?
    /// A team account handle to post as; nil posts as yourself.
    public var postAs: String?
    /// PeerTube-style metadata for an attached video.
    public var videoTitle: String?
    public var videoCategory: String?
    public var videoLicence: String?
    public var contentType: String?

    public init(
        text: String, visibility: Visibility = .public, spoilerText: String? = nil,
        sensitive: Bool = false, language: String? = nil, inReplyToID: String? = nil,
        mediaIDs: [String] = [], pollOptions: [String] = [], pollExpiresIn: Int? = nil,
        pollMultiple: Bool = false, pollHideTotals: Bool = false, scheduledAt: Date? = nil,
        idempotencyKey: String = UUID().uuidString,
        quotedID: String? = nil, quotePolicy: String? = nil,
        placeID: String? = nil, placeName: String? = nil, placeCountry: String? = nil,
        placeLatitude: Double? = nil, placeLongitude: Double? = nil,
        postAs: String? = nil, videoTitle: String? = nil, videoCategory: String? = nil,
        videoLicence: String? = nil, contentType: String? = nil
    ) {
        self.quotedID = quotedID
        self.quotePolicy = quotePolicy
        self.placeID = placeID
        self.placeName = placeName
        self.placeCountry = placeCountry
        self.placeLatitude = placeLatitude
        self.placeLongitude = placeLongitude
        self.postAs = postAs
        self.videoTitle = videoTitle
        self.videoCategory = videoCategory
        self.videoLicence = videoLicence
        self.contentType = contentType
        self.text = text
        self.visibility = visibility
        self.spoilerText = spoilerText
        self.sensitive = sensitive
        self.language = language
        self.inReplyToID = inReplyToID
        self.mediaIDs = mediaIDs
        self.pollOptions = pollOptions
        self.pollExpiresIn = pollExpiresIn
        self.pollMultiple = pollMultiple
        self.pollHideTotals = pollHideTotals
        self.scheduledAt = scheduledAt
        self.idempotencyKey = idempotencyKey
    }

    var formItems: [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "status", value: text),
            URLQueryItem(name: "visibility", value: visibility.rawValue),
            URLQueryItem(name: "sensitive", value: sensitive ? "true" : "false"),
        ]
        items += .optional("spoiler_text", spoilerText)
        items += .optional("language", language)
        items += .optional("in_reply_to_id", inReplyToID)
        items += .repeated("media_ids", mediaIDs)

        // A poll and media are mutually exclusive, as Mastodon requires.
        if !pollOptions.isEmpty && mediaIDs.isEmpty {
            items += .repeated("poll[options]", pollOptions)
            items.append(
                URLQueryItem(name: "poll[expires_in]", value: String(pollExpiresIn ?? 86_400)))
            items.append(
                URLQueryItem(name: "poll[multiple]", value: pollMultiple ? "true" : "false"))
            items.append(
                URLQueryItem(name: "poll[hide_totals]", value: pollHideTotals ? "true" : "false"))
        }
        if let scheduledAt {
            items.append(URLQueryItem(name: "scheduled_at", value: DateParsing.format(scheduledAt)))
        }

        // Nextcloud Social extras. The web composer names the quote `quote_id`
        // and the controller reads `quoted_id`; both go, and a server that
        // knows neither ignores both.
        items += .optional("quoted_id", quotedID)
        items += .optional("quote_id", quotedID)
        items += .optional("quote_policy", quotePolicy)
        if let placeID {
            items.append(URLQueryItem(name: "place_id", value: placeID))
        } else if let placeName, !placeName.isEmpty {
            items.append(URLQueryItem(name: "place_name", value: placeName))
            items += .optional("place_country", placeCountry)
            items += .optional("place_lat", placeLatitude.map { String($0) })
            items += .optional("place_lon", placeLongitude.map { String($0) })
        }
        items += .optional("post_as", postAs)
        items += .optional("video_title", videoTitle)
        items += .optional("video_category", videoCategory)
        items += .optional("video_licence", videoLicence)
        items += .optional("content_type", contentType)
        return items
    }
}
