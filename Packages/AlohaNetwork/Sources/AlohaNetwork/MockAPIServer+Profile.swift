// SPDX-License-Identifier: MIT

import Foundation

extension MockAPIServer {
    /// Mock answers for the profile surfaces: Pixelfed's tagged photos and
    /// people-tagging, and `familiar_followers`. `nil` means "not mine".
    ///
    /// The `api/v1/accounts/{id}/…` sub-routes (highlights, featured_tags,
    /// note, pin, unpin, remove_from_followers, lists) and the list-member
    /// routes are caught by the main switch before this runs.
    func profileMock(
        route: String, url: URL, method: String, query: [URLQueryItem], body: Data?
    ) -> (Data, HTTPURLResponse)? {
        let taggedPrefix = "api/v1.1/accounts/"
        if route.hasPrefix(taggedPrefix), route.hasSuffix("/tagged") {
            // Bob is tagged in Alice's photographs.
            let id =
                route.dropFirst(taggedPrefix.count).split(separator: "/").first.map(String.init)
                ?? ""
            guard ["1", "2"].contains(id) else {
                return respond(url: url, status: 404, body: #"{"error":"Record not found"}"#)
            }
            let photos = statusFixtures.filter { row in
                let media = row["media_attachments"] as? [[String: Any]] ?? []
                return media.contains { ($0["type"] as? String) == "image" }
            }
            let maxID = query.first { $0.name == "max_id" }?.value.flatMap(Int.init)
            let page = photos.filter {
                maxID == nil || (Int($0["id"] as? String ?? "") ?? 0) < maxID!
            }
            return respond(url: url, status: 200, json: Array(page.prefix(40)))
        }

        switch route {
        case "api/v1.1/compose/tag" where method == "POST":
            let fields = formFields(body)
            let handles = fields.filter { $0.key.hasPrefix("accounts") }.values.sorted()
            let people = handles.map { handle -> [String: Any] in
                let username = handle.split(separator: "@").first.map(String.init) ?? handle
                return ["id": username == "bob" ? "2" : "1", "acct": handle, "username": username]
            }
            return respond(url: url, status: 200, json: ["tagged_people": people])

        case "api/v1.1/compose/tag/untagme" where method == "POST":
            return respond(url: url, status: 200, json: ["untagged": true])

        case "api/v1/accounts/familiar_followers":
            let ids = query.filter { $0.name == "id[]" || $0.name == "id" }.compactMap(\.value)
            return respond(
                url: url, status: 200,
                json: ids.map { id -> [String: Any] in
                    [
                        "id": id,
                        "accounts": id == "2"
                            ? [Fixtures.account(id: "1", username: "alice", host: host)] : [],
                    ]
                })

        default:
            return nil
        }
    }
}
