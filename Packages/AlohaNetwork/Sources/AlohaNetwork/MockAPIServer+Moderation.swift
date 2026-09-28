// SPDX-License-Identifier: MIT

import Foundation

/// The surfaces added after the first pass: keyword filters, "Your year",
/// about-this-server, the moderator's screens, and the two conversation
/// actions. Each answers from here so the screenshot tour has something to
/// draw rather than an error strip.
extension MockAPIServer {
    func moderationMock(
        route: String, url: URL, method: String, query: [URLQueryItem], body: Data?
    ) -> (Data, HTTPURLResponse)? {
        switch (route, method) {

        // MARK: Filters

        case ("api/v2/filters", "POST"):
            let fields = formFields(body)
            return respond(
                url: url, status: 200,
                json: filterPayload(
                    id: "f\(Int.random(in: 100...999))",
                    title: fields["title"] ?? "",
                    action: fields["filter_action"] ?? "warn"))

        case (let route, "PUT") where route.hasPrefix("api/v2/filters/"):
            let fields = formFields(body)
            let id = String(route.dropFirst("api/v2/filters/".count))
            return respond(
                url: url, status: 200,
                json: filterPayload(
                    id: id, title: fields["title"] ?? "", action: fields["filter_action"] ?? "warn")
            )

        // MARK: Conversations

        case ("api/v1/conversations/read_all", "POST"):
            return respond(url: url, status: 200, json: ["count": 2])

        case ("api/v1/conversations/unread_count", "GET"):
            return respond(url: url, status: 200, json: ["count": 1])

        case (let route, "DELETE") where route.hasPrefix("api/v1/conversations/"):
            return respond(url: url, status: 200, body: "{}")

        // MARK: About this server

        case ("api/v1/instance/peers", "GET"):
            return respond(
                url: url, status: 200,
                json: ["mastodon.social", "pixelfed.social", "peertube.example", host])

        case ("api/v1/instance/activity", "GET"):
            // Strings, as the real route sends them.
            let monday = Int(Date().timeIntervalSince1970 / 604_800) * 604_800
            return respond(
                url: url, status: 200,
                json: (0..<12).map { week in
                    [
                        "week": String(monday - week * 604_800),
                        "statuses": String(max(0, 40 - week * 3)),
                        "logins": "0",
                        "registrations": "0",
                    ]
                })

        case ("api/v1/instance/domain_blocks", "GET"):
            return respond(
                url: url, status: 200,
                json: [
                    [
                        "domain": "spam.example",
                        "digest": "3f1a",
                        "severity": "suspend",
                        "comment": "",
                    ]
                ])

        // MARK: Your year

        case ("api/v1/annual_reports", "GET"):
            return respond(url: url, status: 200, json: annualReportsPayload())

        case (let route, "GET") where route.hasPrefix("api/v1/annual_reports/"):
            if route.hasSuffix("/state") {
                return respond(url: url, status: 200, json: ["state": "available"])
            }
            return respond(url: url, status: 200, json: annualReportsPayload())

        case (let route, "POST") where route.hasPrefix("api/v1/annual_reports/"):
            return respond(url: url, status: 200, body: "{}")

        // MARK: The colour the server wears

        case ("ocs/capabilities", "GET"):
            // Nextcloud's shipped blue, with the two variants it computes so
            // the app has something real to pick between in light and dark.
            return respond(
                url: url, status: 200,
                json: [
                    "ocs": [
                        "meta": ["status": "ok", "statuscode": 200],
                        "data": [
                            "capabilities": [
                                "theming": [
                                    "name": "Test Nextcloud",
                                    "slogan": "a safe home for your data",
                                    "color": "#0082c9",
                                    "color-element-bright": "#0082c9",
                                    "color-element-dark": "#3ea4e4",
                                    "color-text": "#ffffff",
                                ]
                            ]
                        ],
                    ]
                ])

        // MARK: One status's link preview, asked for on its own

        case (let route, "GET")
        where route.hasPrefix("api/v1/statuses/")
            && route.hasSuffix("/card"):
            // The fixture statuses that have a card already inline it, so the
            // one asked for here is the other kind: a post whose preview the
            // server builds when a reader opens it.
            return respond(url: url, status: 200, json: Fixtures.card(host: host))

        // MARK: The instance's own directory, and who to message

        case ("api/v1/directory", "GET"):
            let order = query.first { $0.name == "order" }?.value ?? "active"
            // Two different orders have to look different, or a picker that
            // does nothing looks like a picker that is broken.
            let people =
                (order == "new")
                ? [("5", "newcomer"), ("2", "bob")]
                : [("2", "bob"), ("5", "newcomer")]
            return respond(
                url: url, status: 200,
                json: people.map { Fixtures.account(id: $0.0, username: $0.1, host: host) })

        case ("api/v1.1/direct/compose/mutuals", "GET"):
            return respond(
                url: url, status: 200,
                json: [Fixtures.account(id: "2", username: "bob", host: host)])

        // MARK: Deleting the Social account

        case ("api/v1/account/delete", "POST"):
            return respond(url: url, status: 200, json: ["deleted": true])

        default:
            break
        }

        guard route.hasPrefix("api/v1/admin/") else { return nil }
        return adminAnswer(route: route, url: url, method: method)
    }

    // MARK: - The moderator's screens

    private func adminAnswer(
        route: String, url: URL, method: String
    ) -> (Data, HTTPURLResponse)? {
        // Mock mode is always an administrator; the real server decides, and a
        // 403 there is what hides the section.
        switch (route, method) {
        case ("api/v1/admin/reports", "GET"):
            return respond(url: url, status: 200, json: [adminReport(id: "1")])

        case ("api/v1/admin/accounts", "GET"), ("api/v2/admin/accounts", "GET"):
            return respond(
                url: url, status: 200,
                json: [
                    adminAccount(id: "2", username: "bob", domain: "other.example"),
                    adminAccount(
                        id: "3", username: "mallory", domain: "spam.example", suspended: true),
                ])

        case ("api/v1/admin/trends/tags", "GET"):
            return respond(
                url: url, status: 200,
                json: ["nextcloud", "fediverse"].map { Fixtures.tag($0, host: host) })

        case ("api/v1/admin/trends/statuses", "GET"):
            return respond(url: url, status: 200, json: [Fixtures.status(index: 0, host: host)])

        case ("api/v1/admin/trends/links", "GET"):
            return respond(
                url: url, status: 200,
                json: [
                    [
                        "url": "https://example.org/article",
                        "title": "Something everybody is reading",
                        "description": "",
                        "type": "link",
                    ]
                ])

        default:
            break
        }

        if route.hasPrefix("api/v1/admin/reports/"), method == "GET" {
            let id = route.split(separator: "/").dropFirst(4).first.map(String.init) ?? "1"
            return respond(url: url, status: 200, json: adminReport(id: id))
        }

        // Every write — resolve, reopen, assign, the account actions and the
        // trend decisions — answers `{}`, as the real ones do.
        if method == "POST" || method == "PUT" {
            return respond(url: url, status: 200, body: "{}")
        }

        return nil
    }

    // MARK: - Payloads

    private func filterPayload(id: String, title: String, action: String) -> [String: Any] {
        [
            "id": id,
            "title": title,
            "context": ["home", "public"],
            "expires_at": NSNull(),
            "filter_action": action,
            "keywords": [["id": "k1", "keyword": title.lowercased(), "whole_word": false]],
            "statuses": [],
        ]
    }

    private func annualReportsPayload() -> [String: Any] {
        let year = Calendar.current.component(.year, from: Date()) - 1
        let status = Fixtures.status(index: 0, host: host)
        return [
            "annual_reports": [
                [
                    "year": year,
                    "data": [
                        "archetype": "oracle",
                        "time_series": (1...12).map { month in
                            ["month": month, "statuses": month * 2, "followers": month % 4]
                        },
                        "top_hashtags": [
                            ["name": "nextcloud", "count": 12],
                            ["name": "fediverse", "count": 7],
                        ],
                        "top_statuses": [
                            "by_reblogs": status["id"] as? String ?? "1",
                            "by_replies": NSNull(),
                            "by_favourites": status["id"] as? String ?? "1",
                        ],
                    ],
                    "schema_version": 1,
                    "share_url": NSNull(),
                    "account_id": "1",
                ]
            ],
            "accounts": [Fixtures.account(id: "1", username: "alice", host: host)],
            "statuses": [status],
        ]
    }

    private func adminAccount(
        id: String, username: String, domain: String, suspended: Bool = false
    ) -> [String: Any] {
        [
            "id": id,
            "username": username,
            "domain": domain,
            "created_at": "2025-03-04T09:00:00.000Z",
            "email": "",
            "ip": NSNull(),
            "ips": [],
            "locale": "",
            "invite_request": NSNull(),
            "role": NSNull(),
            "confirmed": true,
            "approved": true,
            "disabled": false,
            "silenced": false,
            "suspended": suspended,
            "sensitized": false,
            "created_by_application_id": NSNull(),
            "invited_by_account_id": NSNull(),
            "account": Fixtures.account(id: id, username: username, host: host),
        ]
    }

    private func adminReport(id: String) -> [String: Any] {
        [
            "id": id,
            "action_taken": false,
            "action_taken_at": NSNull(),
            "category": "spam",
            "comment": "Posting the same link under every hashtag.",
            "forwarded": false,
            "created_at": "2026-09-20T08:30:00.000Z",
            "updated_at": "2026-09-20T08:30:00.000Z",
            "account": Fixtures.account(id: "1", username: "alice", host: host),
            "target_account": Fixtures.account(id: "3", username: "mallory", host: host),
            "assigned_account": NSNull(),
            "action_taken_by_account": NSNull(),
            "statuses": [Fixtures.status(index: 1, host: host)],
            "rules": [],
        ]
    }
}
