// SPDX-License-Identifier: MIT

import Foundation

extension MockAPIServer {
    /// Mock answers for the account surfaces: featured tags, authorized apps,
    /// the portfolio, migration, statistics, channels and the profile-picture
    /// routes. `nil` means "not mine".
    ///
    /// `api/v1/accounts/update_credentials` never arrives here: the main
    /// switch's `api/v1/accounts/` prefix case answers it first.
    func accountMock(
        route: String, url: URL, method: String, query: [URLQueryItem], body: Data?
    ) -> (Data, HTTPURLResponse)? {
        let alice = Fixtures.account(id: "1", username: "alice", host: host)

        switch route {
        // MARK: Featured tags
        case "api/v1/featured_tags" where method == "GET":
            return respond(url: url, status: 200, json: Fixtures.featuredTags(host: host))
        case "api/v1/featured_tags" where method == "POST":
            let name = formFields(body)["name"] ?? "new"
            return respond(
                url: url, status: 200,
                json: [
                    "id": "ft-\(name)", "name": name, "url": "https://\(host)/tags/\(name)",
                    "statuses_count": 0, "last_status_at": NSNull(),
                ])
        case "api/v1/featured_tags/suggestions":
            return respond(
                url: url, status: 200, json: [["name": "photography"], ["name": "fediverse"]])
        case let route where route.hasPrefix("api/v1/featured_tags/") && method == "DELETE":
            return respond(url: url, status: 200, body: "{}")

        // MARK: Authorized apps
        case "api/v1/authorized_apps" where method == "GET":
            return respond(
                url: url, status: 200,
                json: [
                    [
                        "id": "app-1", "name": "Aloha Social", "website": "https://nextcloud.com",
                        "created_at": 1_758_000_000, "signed_in": 1_758_000_000,
                        "last_used_at": 1_758_800_000,
                        "scopes": ["read", "write", "follow", "push"],
                    ],
                    [
                        "id": "app-2", "name": "Elk", "website": "https://elk.zone",
                        "created_at": "2026-08-01T10:00:00.000Z",
                        "signed_in": "2026-08-01T10:00:00.000Z",
                        "last_used_at": NSNull(), "scopes": "read write",
                    ],
                ])
        case let route where route.hasPrefix("api/v1/authorized_apps/") && method == "DELETE":
            return respond(url: url, status: 200, body: "{}")

        // MARK: Profile pictures
        case "api/v1/profile/avatar" where method == "DELETE",
            "api/v1/profile/header" where method == "DELETE":
            var account = alice
            account[route.hasSuffix("avatar") ? "avatar" : "header"] = ""
            return respond(url: url, status: 200, json: account)

        // MARK: Portfolio
        case "api/v1.1/portfolio" where method == "GET":
            return respond(
                url: url, status: 200,
                json: Fixtures.portfolio(host: host, statuses: statusFixtures))
        case "api/v1.1/portfolio" where method == "POST":
            let fields = formFields(body)
            var portfolio = Fixtures.portfolio(host: host, statuses: statusFixtures)
            for key in ["title", "intro", "layout", "source", "collection_id"] {
                if let value = fields[key] { portfolio[key] = value }
            }
            for key in ["active", "show_captions", "show_places", "show_dates", "show_avatar"] {
                if let value = fields[key] { portfolio[key] = value == "1" || value == "true" }
            }
            return respond(url: url, status: 200, json: portfolio)
        case let route where route.hasPrefix("api/v1.1/portfolio/"):
            var page = Fixtures.portfolio(host: host, statuses: statusFixtures)
            page["handle"] = "alice"
            page["avatar"] = "https://\(host)/avatars/alice.png"
            return respond(url: url, status: 200, json: page)
        case "api/v1.1/collections/self":
            return respond(
                url: url, status: 200,
                json: [
                    [
                        "id": "col-1", "title": "Mountains", "description": "",
                        "url": "https://\(host)/c/1",
                        "post_count": 3, "thumbnail": "https://\(host)/media/998.jpg",
                    ]
                ])

        // MARK: Migration
        case "api/v1/migration/export":
            return respond(
                url: url, status: 200, data: Data("PK\u{03}\u{04}mock".utf8),
                headers: [
                    "Content-Type": "application/zip"
                ])
        case let route where route.hasPrefix("api/v1/migration/export/"):
            return respond(
                url: url, status: 200,
                data: Data("Account address,Show boosts\nbob@\(host),true\n".utf8),
                headers: [
                    "Content-Type": "text/csv"
                ])
        case "api/v1/migration/import" where method == "POST":
            return respond(
                url: url, status: 200, json: ["imported": true, "log": ["profile", "3 follows"]])
        case "api/v1/migration/follows", "api/v1/migration/blocks", "api/v1/migration/mutes",
            "api/v1/migration/lists":
            return respond(url: url, status: 200, json: ["imported": 3, "skipped": 1, "failed": 0])
        case "api/v1/migration/posts":
            return respond(url: url, status: 200, json: ["imported": 12, "media": 4])
        case "api/v1/migration/video":
            return respond(
                url: url, status: 200, json: ["imported": 1, "url": formFields(body)["url"] ?? ""])
        case "api/v1/migration/people" where method == "POST":
            return respond(
                url: url, status: 200, json: ["handles": ["bob@\(host)", "nobody@nowhere.test"]])
        case "api/v1/migration/people/find":
            return respond(
                url: url, status: 200,
                json: [
                    "results": [
                        [
                            "handle": "bob@\(host)", "found": true,
                            "account": Fixtures.account(id: "2", username: "bob", host: host),
                        ],
                        ["handle": "nobody@nowhere.test", "found": false],
                    ]
                ])
        case "api/v1/migration/announcement":
            return respond(
                url: url, status: 200,
                json: ["handle": "@alice@\(host)", "address": "https://\(host)/@alice"])
        case "api/v1/migration/aliases":
            let alias = formFields(body)["alias"] ?? query.first { $0.name == "alias" }?.value
            var aliases = ["old@example.test"]
            if method == "POST", let alias { aliases.append(alias) }
            if method == "DELETE", let alias { aliases.removeAll { $0 == alias } }
            return respond(url: url, status: 200, json: ["aliases": aliases])

        // MARK: Statistics
        case "api/v1/statistics":
            let days = Int(query.first { $0.name == "days" }?.value ?? "0") ?? 0
            return respond(url: url, status: 200, json: Fixtures.statistics(host: host, days: days))
        case "api/v1/statistics/export":
            return respond(
                url: url, status: 200, data: Data("metric,value\nposts,42\n".utf8),
                headers: [
                    "Content-Type": "text/csv"
                ])

        // MARK: Channels
        case "api/v1/channels" where method == "GET":
            return respond(url: url, status: 200, json: ["channels": Fixtures.channels(host: host)])
        case "api/v1/channels" where method == "POST":
            let fields = formFields(body)
            var channels = Fixtures.channels(host: host)
            channels.append([
                "id": "ch-\(channels.count + 1)", "handle": fields["handle"] ?? "new",
                "name": fields["name"] ?? "", "description": fields["description"] ?? "",
                "url": "https://\(host)/c/\(fields["handle"] ?? "new")", "videos_count": 0,
            ])
            return respond(url: url, status: 200, json: ["channels": channels])
        case let route where route.hasPrefix("api/v1/channels/") && method == "PUT":
            let fields = formFields(body)
            let id = String(route.dropFirst("api/v1/channels/".count))
            let channels = Fixtures.channels(host: host).map { channel -> [String: Any] in
                guard (channel["id"] as? String) == id else { return channel }
                var copy = channel
                if let name = fields["name"] { copy["name"] = name }
                if let description = fields["description"] { copy["description"] = description }
                return copy
            }
            return respond(url: url, status: 200, json: ["channels": channels])

        default:
            return nil
        }
    }
}

extension Fixtures {
    static func featuredTags(host: String) -> [[String: Any]] {
        [
            [
                "id": "ft-1", "name": "nextcloud", "url": "https://\(host)/tags/nextcloud",
                "statuses_count": 12, "last_status_at": "2026-09-20T10:00:00.000Z",
            ],
            [
                "id": "ft-2", "name": "photography", "url": "https://\(host)/tags/photography",
                "statuses_count": "4", "last_status_at": NSNull(),
            ],
        ]
    }

    static func portfolio(host: String, statuses: [[String: Any]]) -> [String: Any] {
        let pictures = statuses.filter { row in
            let media = row["media_attachments"] as? [[String: Any]] ?? []
            return media.contains { ($0["type"] as? String) == "image" }
        }
        return [
            "active": true, "title": "Alice's pictures", "intro": "Mountains, mostly.",
            "layout": "grid", "source": "recent", "collection_id": NSNull(),
            "show_captions": true, "show_places": true, "show_dates": true, "show_avatar": true,
            "url": "https://\(host)/@alice/portfolio",
            "posts": Array(pictures.prefix(6)),
        ]
    }

    static func statistics(host: String, days: Int) -> [String: Any] {
        [
            "account": ["acct": "alice", "followers": 120, "following": 80],
            "window": ["days": days, "counted": 42, "capped": false],
            "posts": ["total": 42, "originals": 30, "replies": 9, "boosts": 3],
            "engagement": [
                "favourites": 88, "boosts": "21", "replies": 17, "reach": 1450, "silent": 6,
            ],
            "rates": ["engagement": 0.12, "average": 3.0],
            "visibility": ["public": 35, "unlisted": 4, "private": 2, "direct": 1],
            "consistency": ["active_days": 28, "longest_streak": 6, "longest_gap": 9],
            "media": ["pictures": 14, "described": 11],
            "by_month": ["2026-07": 10, "2026-08": 17, "2026-09": 15],
            "engagement_by_month": ["2026-07": 20, "2026-08": 61, "2026-09": 45],
            "activity": [
                "originals": ["2026-07": 7, "2026-08": 12, "2026-09": 11],
                "replies": ["2026-07": 2, "2026-08": 4, "2026-09": 3],
                "boosts": ["2026-07": 1, "2026-08": 1, "2026-09": 1],
            ],
            "partners": [
                "inbound": [["account": "bob@\(host)", "replies": 9]],
                "outbound": [["account": "bob@\(host)", "replies": 5]],
            ],
            "languages": [["name": "en", "count": 40], ["name": "de", "count": 2]],
            "domains": [["name": "example.test", "count": 6]],
            "hashtags": [
                ["name": "nextcloud", "count": 12], ["name": "photography", "count": 4],
            ],
            "network": [:], "growth": [:], "software": [:],
        ]
    }

    static func channels(host: String) -> [[String: Any]] {
        [
            [
                "id": "ch-1", "handle": "alice_channel", "name": "Alice's videos",
                "description": "Talks and walks.", "url": "https://\(host)/c/alice_channel",
                "videos_count": 3, "created_at": "2026-01-01T00:00:00.000Z",
            ]
        ]
    }
}
