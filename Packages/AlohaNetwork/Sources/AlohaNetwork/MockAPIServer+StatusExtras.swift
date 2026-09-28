// SPDX-License-Identifier: MIT

import Foundation

extension MockAPIServer {
    /// Mock answers for the per-status extras: archive, places, albums, and
    /// the status sub-routes the main switch lets through. `nil` means "not
    /// mine".
    func statusExtrasMock(
        route: String, url: URL, method: String, query: [URLQueryItem], body: Data?
    ) -> (Data, HTTPURLResponse)? {
        // MARK: Archive (Pixelfed)

        if route.hasPrefix("api/pixelfed/v1/archive/") {
            let rest = route.dropFirst("api/pixelfed/v1/archive/".count)
            if rest == "list" {
                // The two oldest fixtures stand in for what was archived.
                let archived = statusFixtures.suffix(2).map { row -> [String: Any] in
                    var copy = row
                    copy["archived"] = true
                    return copy
                }
                return respond(url: url, status: 200, json: Array(archived))
            }
            if rest.hasPrefix("add/") || rest.hasPrefix("remove/") {
                return respond(url: url, status: 200, json: ["code": 200])
            }
        }

        // MARK: Places

        if route.hasPrefix("api/v1/places/") {
            let parts = route.dropFirst("api/v1/places/".count).split(separator: "/")
            guard let id = parts.first.map(String.init) else { return nil }
            if parts.count == 1 {
                return respond(url: url, status: 200, json: place(id: id))
            }
            if parts.dropFirst().first == "statuses" {
                let rows = statusFixtures.prefix(6).map { row -> [String: Any] in
                    var copy = row
                    copy["place"] = place(id: id)
                    return copy
                }
                return respond(url: url, status: 200, json: Array(rows))
            }
        }

        // MARK: Albums

        if route == "api/v1/collections" {
            if method == "POST" {
                let fields = formFields(body)
                return respond(
                    url: url, status: 200,
                    json: collection(
                        id: "c\(Int.random(in: 100...999))", title: fields["title"] ?? "Untitled",
                        count: 0))
            }
            return respond(
                url: url, status: 200,
                json: [
                    collection(id: "c1", title: "Holiday", count: 3),
                    collection(id: "c2", title: "Portraits", count: 1),
                ])
        }
        if route.hasPrefix("api/v1/collections/") {
            let parts = route.dropFirst("api/v1/collections/".count).split(separator: "/")
            guard let id = parts.first.map(String.init) else { return nil }
            if parts.count == 1 {
                switch method {
                case "PUT":
                    let fields = formFields(body)
                    return respond(
                        url: url, status: 200,
                        json: collection(
                            id: id, title: fields["title"] ?? "Untitled", count: 3))
                case "DELETE":
                    return respond(url: url, status: 200, body: "{}")
                default:
                    return respond(
                        url: url, status: 200, json: collection(id: id, title: "Holiday", count: 3))
                }
            }
            if parts.dropFirst().first == "items" {
                if method == "GET" {
                    // Album c1 holds the photo fixture; the others are empty.
                    let items =
                        id == "c1"
                        ? statusFixtures.filter {
                            !(($0["media_attachments"] as? [[String: Any]]) ?? []).isEmpty
                        }.prefix(3)
                        : []
                    return respond(url: url, status: 200, json: Array(items))
                }
                return respond(url: url, status: 200, body: "{}")
            }
        }
        if route.hasPrefix("api/v1/accounts/"), route.hasSuffix("/collections") {
            return respond(
                url: url, status: 200,
                json: [
                    collection(id: "c1", title: "Holiday", count: 3)
                ])
        }

        // MARK: Status sub-routes
        //
        // Reached only if the main switch's `api/v1/statuses/` case lets them
        // through; listed here so the shapes exist either way.

        if route.hasPrefix("api/v1/statuses/") {
            let parts = route.dropFirst("api/v1/statuses/".count).split(separator: "/")
            guard let id = parts.first.map(String.init),
                let status = statusFixtures.first(where: { ($0["id"] as? String) == id })
            else { return nil }
            switch parts.dropFirst().first {
            case "delivery":
                return respond(
                    url: url, status: 200,
                    json: [
                        "total": 3, "delivered": 2, "sending": 0, "waiting": 0, "failing": 1,
                        "abandoned": 0, "retention": 604_800,
                        "instances": [
                            [
                                "host": "mastodon.example", "state": "delivered", "tries": 1,
                                "last": "2026-09-20T10:00:00.000Z",
                            ],
                            [
                                "host": "pixelfed.example", "state": "delivered", "tries": 1,
                                "last": "2026-09-20T10:00:00.000Z",
                            ],
                            [
                                "host": "down.example", "state": "failing", "tries": 4,
                                "last": "2026-09-21T10:00:00.000Z",
                            ],
                        ],
                    ])
            case "quotes" where parts.count == 2:
                var quoting = Fixtures.status(index: 700, host: host)
                quoting["id"] = "\(id)-q1"
                quoting["content"] = "<p>Quoting this one.</p>"
                quoting["media_attachments"] = []
                quoting["spoiler_text"] = ""
                quoting["quote_id"] = id
                quoting["account"] = Fixtures.account(id: "2", username: "bob", host: host)
                return respond(url: url, status: 200, json: [quoting])
            case "quotes":
                // …/quotes/{quoting}/revoke
                return respond(url: url, status: 200, body: "{}")
            case "interaction_policy":
                var updated = status
                updated["quote_approval_policy"] =
                    formFields(body)["quote_approval_policy"] ?? "public"
                return respond(url: url, status: 200, json: updated)
            case "pin", "unpin":
                var updated = status
                updated["pinned"] = parts[1] == "pin"
                return respond(url: url, status: 200, json: updated)
            case "dislike", "undislike":
                var updated = status
                let isDislike = parts[1] == "dislike"
                updated["disliked"] = isDislike
                updated["dislikes_count"] = isDislike ? 1 : 0
                return respond(url: url, status: 200, json: updated)
            default:
                return nil
            }
        }

        return nil
    }

    private func place(id: String) -> [String: Any] {
        ["id": id, "name": "Stuttgart", "country": "Germany", "lat": 48.78, "lon": 9.18]
    }

    private func collection(id: String, title: String, count: Int) -> [String: Any] {
        [
            "id": id, "title": title, "description": "", "visibility": "public",
            "url": "https://\(host)/c/\(id)", "post_count": count,
            "thumbnail": "https://\(host)/media/998_small.jpg",
            "updated_at": "2026-09-20T10:00:00.000Z",
        ]
    }
}
