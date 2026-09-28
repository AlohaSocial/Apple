// SPDX-License-Identifier: MIT

import Foundation

extension MockAPIServer {
    /// Mock answers for the Stories surfaces. `nil` means "not mine".
    ///
    /// `api/v1/stories/carousel` is answered by the main switch (an empty
    /// rail) and `api/v1/accounts/{id}/stories` is swallowed by the accounts
    /// prefix there, so neither reaches this.
    func storiesMock(
        route: String, url: URL, method: String, query: [URLQueryItem], body: Data?
    ) -> (Data, HTTPURLResponse)? {
        guard
            route.hasPrefix("api/v1/stories") || route.hasPrefix("api/v1.1/stories")
                || route.hasPrefix("api/v1.2/stories")
        else { return nil }

        // Pixelfed's own name for ending a story early, which the app falls
        // back to where `DELETE /api/v1/stories/{id}` is not served.
        if route.hasPrefix("api/v1.1/stories/self-expire/"), method == "POST" {
            return respond(
                url: url, status: 200, json: ["code": 200, "msg": "Successfully deleted"])
        }

        switch (route, method) {
        case ("api/v1/stories/self", "GET"):
            return respond(url: url, status: 200, json: [ownStory(id: "s1", views: 3)])

        case ("api/v1.2/stories/carousel", "GET"):
            return respond(
                url: url, status: 200,
                json: [
                    "self": [ownStory(id: "s1", views: 3)],
                    "nodes": [
                        [
                            "account": Fixtures.account(id: "2", username: "bob", host: host),
                            "seen": false,
                            "stories": [storyPayload(id: "s2", accountID: "2", username: "bob")],
                        ]
                    ],
                ])

        case ("api/v1/stories", "POST"):
            let fields = formFields(body)
            var story = ownStory(id: "s\(Int.random(in: 100...999))", views: 0)
            story["caption"] = fields["caption"] ?? ""
            story["duration"] = Int(fields["duration"] ?? "") ?? 5
            return respond(url: url, status: 200, json: story)

        default:
            break
        }

        // Per-story routes: seen, react, comment, viewers, reactions, delete.
        let parts = route.split(separator: "/").map(String.init)
        guard parts.count >= 3, let id = parts[safe: 2] else { return nil }
        let action = parts[safe: 3]

        switch (action, method) {
        case (nil, "DELETE"):
            return respond(url: url, status: 200, body: "{}")
        case ("seen", "POST"):
            return respond(url: url, status: 200, json: ["code": 200])
        case ("react", "POST"), ("comment", "POST"):
            var story = storyPayload(id: id, accountID: "2", username: "bob")
            story["seen"] = true
            return respond(url: url, status: 200, json: story)
        case ("viewers", "GET"):
            return respond(
                url: url, status: 200,
                json: [
                    Fixtures.account(id: "2", username: "bob", host: host)
                ])
        case ("reactions", "GET"):
            return respond(
                url: url, status: 200,
                json: [
                    "reactions": [
                        [
                            "id": "r1",
                            "account": Fixtures.account(id: "2", username: "bob", host: host),
                            "reaction": "🔥",
                            "created_at": "2026-09-26T10:00:00.000Z",
                        ],
                        [
                            "id": "r2",
                            "account": Fixtures.account(id: "2", username: "bob", host: host),
                            "comment": "Lovely light.",
                            "created_at": "2026-09-26T10:05:00.000Z",
                        ],
                    ]
                ])
        default:
            return nil
        }
    }

    private func ownStory(id: String, views: Int) -> [String: Any] {
        var story = storyPayload(id: id, accountID: "1", username: "alice")
        story["view_count"] = views
        story["seen"] = true
        return story
    }

    private func storyPayload(id: String, accountID: String, username: String) -> [String: Any] {
        let published = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        let expires = ISO8601DateFormatter().string(from: Date().addingTimeInterval(82_800))
        return [
            "id": id,
            "account": Fixtures.account(id: accountID, username: username, host: host),
            "url": "https://\(host)/media/story-\(id).jpg",
            "preview_url": "https://\(host)/media/story-\(id)_small.jpg",
            "type": "image",
            "caption": "A story from \(username.capitalized).",
            "duration": 5,
            "published_at": published,
            "expires_at": expires,
            "seen": false,
        ]
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
