// SPDX-License-Identifier: MIT

import Foundation

extension MockAPIServer {
    /// Mock answers for the Discovery surfaces: starter packs, directories,
    /// the follow graph and Pixelfed's discover routes. `nil` means "not mine".
    ///
    /// `api/v1/tags/{name}/related` is answered by the main switch's tag
    /// prefix handler before it gets here, so it is not mocked.
    func discoveryMock(
        route: String, url: URL, method: String, query: [URLQueryItem], body: Data?
    ) -> (Data, HTTPURLResponse)? {
        let alice = Fixtures.account(id: "1", username: "alice", host: host)
        let bob = Fixtures.account(id: "2", username: "bob", host: host)

        switch route {
        case "api/v1/starter_packs":
            return respond(
                url: url, status: 200,
                json: [
                    [
                        "slug": "nextcloud-people", "name": "Nextcloud people",
                        "description": "The people who build and run Nextcloud.",
                        "size": 2, "handles": ["alice@\(host)", "bob@\(host)"],
                    ],
                    [
                        "slug": "photographers", "name": "Photographers",
                        "description": "Pictures every day.", "size": 1, "handles": ["bob@\(host)"],
                    ],
                ])

        case "api/v1/starter_packs/nextcloud-people":
            return respond(
                url: url, status: 200,
                json: [
                    "slug": "nextcloud-people", "name": "Nextcloud people",
                    "description": "The people who build and run Nextcloud.",
                    "size": 3, "handles": ["alice@\(host)", "bob@\(host)", "carol@gone.example"],
                    "accounts": [alice, bob],
                ])

        case "api/v1/starter_packs/photographers":
            return respond(
                url: url, status: 200,
                json: [
                    "slug": "photographers", "name": "Photographers",
                    "description": "Pictures every day.", "size": 1,
                    "handles": ["bob@\(host)"], "accounts": [bob],
                ])

        case "api/v1/starter_packs/nextcloud-people/follow",
            "api/v1/starter_packs/photographers/follow":
            guard method == "POST" else { return nil }
            return respond(url: url, status: 200, json: [bob])

        case "api/v1/directories":
            return respond(
                url: url, status: 200,
                json: [
                    ["host": host, "kind": "local", "label": "This server"],
                    ["host": "mastodon.example", "kind": "mastodon", "label": "mastodon.example"],
                ])

        case "api/v1/directories/search":
            let q = (query.first { $0.name == "q" }?.value ?? "").lowercased()
            var carol = Fixtures.account(id: "3", username: "carol", host: "mastodon.example")
            carol["acct"] = "carol@mastodon.example"
            let accounts = q.isEmpty || "carol".contains(q) ? [carol] : []
            return respond(
                url: url, status: 200,
                json: [
                    "accounts": accounts,
                    "sources": [
                        ["host": "mastodon.example", "status": "ok", "count": accounts.count]
                    ],
                ])

        case "api/v1/directories/hashtags":
            return respond(
                url: url, status: 200,
                json: [
                    "hashtags": ["mastodon", "caturday"].map {
                        Fixtures.tag($0, host: "mastodon.example")
                    },
                    "sources": [["host": "mastodon.example", "status": "ok", "count": 2]],
                ])

        case "api/v1/follow_graph/status":
            return respond(
                url: url, status: 200, json: ["worthwhile": true, "following": 80, "needs": 5])

        case "api/v1/follow_graph":
            return respond(
                url: url, status: 200,
                json: [
                    "suggestions": [["account": bob, "count": 3, "via": [alice]]],
                    "asked": 12, "needs": 5,
                ])

        case "api/v2/discover/posts":
            let media = query.first { $0.name == "media" }?.value ?? "image"
            let wanted = media == "video" ? "video" : "image"
            let rows = statusFixtures.filter { row in
                let attachments = row["media_attachments"] as? [[String: Any]] ?? []
                return attachments.contains { ($0["type"] as? String) == wanted }
            }
            return respond(url: url, status: 200, json: Array(rows.prefix(12)))

        case "api/v1/trends/statuses":
            let rows = statusFixtures.filter {
                !(($0["media_attachments"] as? [[String: Any]]) ?? []).isEmpty
            }
            return respond(url: url, status: 200, json: Array(rows.prefix(12)))

        case "api/v1.1/discover/categories":
            return respond(
                url: url, status: 200,
                json: [
                    "categories": [
                        ["id": 1, "name": "Nature", "hashtags": ["nature", "birds", "landscape"]],
                        ["id": 2, "name": "Open source", "hashtags": ["nextcloud", "opensource"]],
                    ]
                ])

        case "api/v1.1/discover/accounts/popular":
            return respond(url: url, status: 200, json: [alice, bob])

        default:
            return nil
        }
    }
}
