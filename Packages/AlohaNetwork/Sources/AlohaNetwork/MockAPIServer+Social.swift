// SPDX-License-Identifier: MIT

#if DEBUG
    import Foundation

    // Aloha Social's reader settings, its Bluesky side, shared moderation lists,
    // the link timeline and the notification inbox's bulk routes. Every one 404s
    // on a stock Mastodon, as the real server's absence would.

    private nonisolated(unsafe) var socialSettingsStorage = SocialSettingsFixture()

    private struct SocialSettingsFixture {
        var hideAI = false
        /// Off in the mock, although the real server hides counts by default:
        /// the screen tours photograph rows with their numbers on, and a mock
        /// that turned them off would change every picture they take.
        var hideCounts = false
        var directMessagesFrom = "all"
        var delivery: [String: Any] = [
            "mode": "instant", "times": ["08:00"],
            "passthrough": ["direct": true, "mentions_from_followed": true],
            "quiet": ["from": "", "to": ""],
        ]
        var feeds: [[String: Any]] = [
            [
                "uri": "at://did:plc:mock/app.bsky.feed.generator/cats", "type": "feed",
                "name": "Cats", "description": "Only cats.", "avatar": "",
                "creator": "mock.bsky.social", "pinned": true,
            ]
        ]
        var blueskyActive = true
        var publishBlocks = false
        var moderationLists: [[String: Any]] = []
    }

    extension MockAPIServer {
        private var socialSettings: SocialSettingsFixture {
            get { socialSettingsStorage }
            set { socialSettingsStorage = newValue }
        }

        private var servesAlohaSocial: Bool {
            configuration == .nextcloudSocialWithRewrite
                || configuration == .nextcloudSocialWithoutRewrite
        }

        /// `nil` means "not mine".
        func socialMock(
            route: String, url: URL, method: String, query: [URLQueryItem], body: Data?
        ) -> (Data, HTTPURLResponse)? {
            let isMine =
                route.hasPrefix("api/v1/social/") || route == "api/v1/timelines/link"
                || route == "api/v1/timelines/bluesky"
                || route.hasPrefix("api/v1/account/")
                || route == "api/v1/notifications/requests/accept"
                || route == "api/v1/notifications/requests/dismiss"
            guard isMine else { return nil }
            guard servesAlohaSocial else {
                return respond(url: url, status: 404, body: #"{"error":"Not found"}"#)
            }
            let fields = jsonOrFormFields(body)

            switch route {
            // MARK: Reader settings
            case "api/v1/social/ai_content":
                if method == "PATCH", let hide = fields["hide"] { socialSettings.hideAI = hide }
                return respond(url: url, status: 200, json: ["hide": socialSettings.hideAI])

            case "api/v1/social/counts":
                if method == "PATCH", let hide = fields["hide"] { socialSettings.hideCounts = hide }
                return respond(url: url, status: 200, json: ["hide": socialSettings.hideCounts])

            case "api/v1/social/direct_messages":
                if method == "PATCH", let from = formFields(body)["from"] {
                    guard ["all", "following", "none"].contains(from) else {
                        return respond(
                            url: url, status: 422,
                            body: #"{"error":"from must be all, following or none"}"#)
                    }
                    socialSettings.directMessagesFrom = from
                }
                return respond(
                    url: url, status: 200, json: ["from": socialSettings.directMessagesFrom])

            case "api/v1/social/notification_delivery":
                if method == "PATCH", let body,
                    let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                {
                    for (key, value) in object { socialSettings.delivery[key] = value }
                }
                return respond(url: url, status: 200, json: socialSettings.delivery)

            // MARK: Notification inbox
            case "api/v1/notifications/requests/accept", "api/v1/notifications/requests/dismiss":
                return respond(url: url, status: 200, body: "{}")

            case "api/v1/social/notifications/allowed":
                return respond(
                    url: url, status: 200,
                    json: [Fixtures.account(id: "2", username: "bob", host: host)])

            case let route where route.hasPrefix("api/v1/social/notifications/allowed/"):
                return respond(url: url, status: 200, body: "{}")

            case "api/v1/social/notifications/policy/notice/dismiss":
                return respond(
                    url: url, status: 200, body: #"{"for_not_following":"accept","notice":false}"#)

            // MARK: Bluesky
            case "api/v1/social/bluesky/feeds":
                switch method {
                case "POST":
                    let feed: [String: Any] = [
                        "uri": formFields(body)["feed"] ?? "", "type": "feed", "name": "Added",
                        "description": "", "avatar": "", "creator": "", "pinned": true,
                    ]
                    socialSettings.feeds.append(feed)
                    return respond(url: url, status: 200, json: ["feed": feed])
                case "DELETE":
                    let uri = query.first { $0.name == "uri" }?.value ?? ""
                    socialSettings.feeds.removeAll { ($0["uri"] as? String) == uri }
                    return respond(url: url, status: 200, body: "[]")
                default:
                    return respond(url: url, status: 200, json: ["feeds": socialSettings.feeds])
                }

            case "api/v1/social/bluesky/feeds/suggested":
                return respond(
                    url: url, status: 200,
                    json: [
                        "feeds": [
                            [
                                "uri": "at://did:plc:mock/app.bsky.feed.generator/science",
                                "type": "feed", "name": "Science", "description": "Papers.",
                                "avatar": "", "creator": "science.bsky.social",
                            ]
                        ]
                    ])

            case "api/v1/social/bluesky/identity", "api/v1/social/bluesky/state":
                if route.hasSuffix("/state"), let active = fields["active"] {
                    socialSettings.blueskyActive = active
                }
                return respond(url: url, status: 200, json: blueskyIdentity)

            case "api/v1/social/bluesky/publish-blocks":
                if let publish = fields["publish"] { socialSettings.publishBlocks = publish }
                return respond(
                    url: url, status: 200, json: ["publish_blocks": socialSettings.publishBlocks])

            case "api/v1/timelines/bluesky", "api/v1/timelines/link":
                return respond(url: url, status: 200, json: Array(statusFixtures.prefix(5)))

            // MARK: Shared moderation lists
            case "api/v1/social/moderation_lists":
                switch method {
                case "POST":
                    let form = formFields(body)
                    let list: [String: Any] = [
                        "uri": form["url"] ?? "", "name": "Subscribed list",
                        "kind": form["kind"] ?? "mute", "accounts": 0,
                    ]
                    socialSettings.moderationLists.append(list)
                    return respond(url: url, status: 200, json: list)
                case "DELETE":
                    let uri = query.first { $0.name == "uri" }?.value ?? ""
                    let removed = socialSettings.moderationLists.first {
                        ($0["uri"] as? String) == uri
                    }
                    socialSettings.moderationLists.removeAll { ($0["uri"] as? String) == uri }
                    return respond(url: url, status: 200, json: removed ?? [:])
                default:
                    return respond(url: url, status: 200, json: socialSettings.moderationLists)
                }

            // MARK: Local account info
            case let route where route.hasPrefix("api/v1/account/") && route.hasSuffix("/info"):
                let username = route.dropFirst("api/v1/account/".count).dropLast("/info".count)
                var account = Fixtures.account(id: "1", username: String(username), host: host)
                account["bluesky"] = [
                    "handle": "\(username).\(host)", "did": "did:plc:mock\(username)",
                    "url": "https://bsky.app/profile/\(username).\(host)", "native": false,
                    "active": socialSettings.blueskyActive,
                ]
                return respond(url: url, status: 200, json: account)

            default:
                return respond(url: url, status: 404, body: #"{"error":"Not found"}"#)
            }
        }

        private var blueskyIdentity: [String: Any] {
            [
                "handle": "alice.\(host)", "did": "did:plc:mockalice",
                "url": "https://bsky.app/profile/alice.\(host)", "state": "active",
                "active": socialSettings.blueskyActive, "recovery_key": false,
                "assigned_handle": "alice.\(host)", "custom_handle": "",
                "custom_handle_broken": false, "publish_blocks": socialSettings.publishBlocks,
            ]
        }

        /// Booleans from a JSON body, or the `1`/`0` and `true`/`false` of a form.
        private func jsonOrFormFields(_ body: Data?) -> [String: Bool] {
            guard let body else { return [:] }
            if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                return object.compactMapValues { $0 as? Bool }
            }
            return formFields(body).compactMapValues { value in
                switch value.lowercased() {
                case "1", "true": true
                case "0", "false": false
                default: nil
                }
            }
        }
    }
#endif
