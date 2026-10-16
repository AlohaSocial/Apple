// SPDX-License-Identifier: MIT

import Foundation

extension MockAPIServer {
    /// Mock answers for the interests, memories, review-queue
    /// and announcement-reaction surfaces. `nil` means "not mine".
    func interestsMock(
        route: String, url: URL, method: String, query: [URLQueryItem], body: Data?
    ) -> (Data, HTTPURLResponse)? {
        switch route {
        // MARK: My interests
        case "api/v1/interests":
            if method == "POST" {
                let tag = formFields(body)["tag"] ?? ""
                if !tag.isEmpty, !interestsState.tags.contains(tag) {
                    interestsState.tags.append(tag)
                }
            }
            return respond(url: url, status: 200, json: interestsState.json)

        case "api/v1/interests/reset":
            interestsState = InterestsFixture()
            interestsState.tags = []
            return respond(url: url, status: 200, json: interestsState.json)

        case "api/v1/interests/settings":
            let fields = formFields(body)
            if let learning = fields["learning"] {
                interestsState.learning = learning == "1" || learning == "true"
            }
            if let paused = fields["paused"] {
                interestsState.paused = paused == "1" || paused == "true"
            }
            return respond(url: url, status: 200, json: interestsState.settingsJSON)

        case "api/v1/interests/signals":
            return respond(url: url, status: 204)

        case "api/v1/timelines/interests":
            let limit = Int(query.first { $0.name == "limit" }?.value ?? "") ?? 20
            let maxID = query.first { $0.name == "max_id" }?.value
            var rows = statusFixtures.filter {
                !(($0["media_attachments"] as? [[String: Any]]) ?? []).isEmpty == false || true
            }
            rows = rows.map { row in
                var copy = row
                let index = row["id"] as? String ?? ""
                copy["content"] = "<p>Interests post \(index) about #nextcloud.</p>"
                return copy
            }
            if let maxID, let cutoff = Int(maxID) {
                rows = rows.filter { Int($0["id"] as? String ?? "") ?? 0 < cutoff }
            }
            return respond(url: url, status: 200, json: Array(rows.prefix(limit)))

        case let route where route.hasPrefix("api/v1/interests/less/"):
            return respond(url: url, status: 200, json: [])

        case let route where route.hasPrefix("api/v1/interests/"):
            // {tag}, {tag}/pin, {tag}/unpin, {tag}/move
            let parts = route.dropFirst("api/v1/interests/".count).split(separator: "/")
            guard let tag = parts.first?.removingPercentEncoding else { return nil }
            switch (method, parts.dropFirst().first) {
            case ("DELETE", nil):
                interestsState.tags.removeAll { $0 == tag }
            case ("POST", "pin"):
                interestsState.pinned.insert(tag)
            case ("POST", "unpin"):
                interestsState.pinned.remove(tag)
            default:
                break
            }
            return respond(url: url, status: 200, json: interestsState.json)

        // MARK: Memories
        case "api/v1/memories/on_this_day":
            // Two posts from earlier years on today's date.
            let calendar = Calendar(identifier: .gregorian)
            let today = calendar.dateComponents([.month, .day], from: Date())
            let rows = [1, 3].map { yearsAgo -> [String: Any] in
                var row = Fixtures.status(index: 700 + yearsAgo, host: host)
                var components = DateComponents()
                components.year = (calendar.component(.year, from: Date())) - yearsAgo
                components.month = today.month
                components.day = today.day
                components.hour = 10
                let date = calendar.date(from: components) ?? Date()
                row["id"] = "memory-\(yearsAgo)"
                row["created_at"] = ISO8601DateFormatter().string(from: date)
                row["content"] = "<p>Something I wrote \(yearsAgo) year(s) ago today.</p>"
                row["media_attachments"] = []
                row["spoiler_text"] = ""
                return row
            }
            return respond(url: url, status: 200, json: rows)

        case "api/v1/memories/recap":
            if method == "POST" {
                let enabled = formFields(body)["enabled"] ?? "0"
                recapEnabled = enabled == "1" || enabled == "true"
                return respond(url: url, status: 200, json: ["enabled": recapEnabled])
            }
            let recap: [String: Any] =
                recapEnabled
                ? ["enabled": true, "this_week": 4, "last_week": 2] : ["enabled": false]
            return respond(url: url, status: 200, json: recap)

        // MARK: Review queue
        case "api/v1/review":
            return respond(
                url: url, status: 200,
                json: [
                    "held": heldPosts,
                    "reasons": [
                        "Your first post here",
                        "Videos are looked at before they are published here",
                    ],
                ])

        case let route where route.hasPrefix("api/v1/review/") && method == "DELETE":
            let id = String(route.dropFirst("api/v1/review/".count))
            heldPosts.removeAll { ($0["id"] as? String) == id }
            return respond(url: url, status: 200, json: ["withdrawn": id])

        // MARK: Announcement reactions
        case let route where route.hasPrefix("api/v1/announcements/"):
            return respond(url: url, status: 200, json: [:])

        default:
            return nil
        }
    }
}

/// What the mock remembers between requests, so a toggle or an add shows up
/// on the next read the way it would on a server.
struct InterestsFixture {
    var learning = true
    var paused = false
    var tags = ["nextcloud", "photography", "fediverse", "opensource"]
    var pinned: Set<String> = ["nextcloud"]

    var settingsJSON: [String: Any] {
        ["learning": learning, "paused": paused, "languages": ["en"]]
    }

    var json: [String: Any] {
        [
            "settings": settingsJSON,
            "interests": tags.enumerated().map { offset, tag in
                [
                    "tag": tag, "score": Double(tags.count - offset) / Double(tags.count),
                    "pinned": pinned.contains(tag),
                ]
            },
            "candidates": [["tag": "swift", "score": 0.2], ["tag": "cycling", "score": 0.1]],
            "thin": tags.isEmpty,
        ]
    }
}

private nonisolated(unsafe) var interestsStateStorage = InterestsFixture()
private nonisolated(unsafe) var recapEnabledStorage = true
private nonisolated(unsafe) var heldPostsStorage: [[String: Any]] = [
    [
        "id": "h1", "created_at": "2026-09-26T12:00:00Z", "spoiler_text": "",
        "text": "My first post here, waiting for a look.", "media_count": 0,
        "reason": "Your first post here",
    ]
]

extension MockAPIServer {
    // The actor is the only reader and writer, so these globals are safe in
    // practice; they exist because an extension cannot add stored properties.
    fileprivate var interestsState: InterestsFixture {
        get { interestsStateStorage }
        set { interestsStateStorage = newValue }
    }
    fileprivate var recapEnabled: Bool {
        get { recapEnabledStorage }
        set { recapEnabledStorage = newValue }
    }
    fileprivate var heldPosts: [[String: Any]] {
        get { heldPostsStorage }
        set { heldPostsStorage = newValue }
    }
}
