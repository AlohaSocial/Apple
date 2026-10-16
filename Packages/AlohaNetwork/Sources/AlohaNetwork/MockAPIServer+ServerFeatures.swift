// SPDX-License-Identifier: MIT

import Foundation

// The import queue, moving, Bluesky discovery and the smaller routes the
// server answers, shaped as the real one shapes them (`MigrationController`,
// `AtprotoFeedsController`, `ImportJob::jsonSerialize`). Every Aloha Social
// one 404s on a stock Mastodon, as its absence there would.

private nonisolated(unsafe) var serverFeaturesStorage = ServerFeaturesFixture()

private struct ServerFeaturesFixture {
    var imports: [[String: Any]] = []
    var nextImportID = 100
    var movedTo: String?
    var movedAt = 0
    var filesComments = false
    var customHandle = ""
    var filterStatuses: [String: [[String: Any]]] = [:]
    var nextFilterStatusID = 500
}

extension MockAPIServer {
    private var serverFeatures: ServerFeaturesFixture {
        get { serverFeaturesStorage }
        set { serverFeaturesStorage = newValue }
    }

    private var answersAsAlohaSocial: Bool {
        configuration == .nextcloudSocialWithRewrite
            || configuration == .nextcloudSocialWithoutRewrite
    }

    /// `nil` means "not mine": the routes already mocked elsewhere — the
    /// synchronous list imports among them, which is how an older server
    /// answered — keep their answers.
    func serverFeaturesMock(
        route: String, url: URL, method: String, query: [URLQueryItem], body: Data?
    ) -> (Data, HTTPURLResponse)? {
        let aloha = answersAsAlohaSocial
        let notFound = respond(url: url, status: 404, body: #"{"error":"Not found"}"#)
        let form = formFields(body)

        switch (route, method) {
        // MARK: The import queue
        case ("api/v1/migration/imports", "GET"):
            guard aloha else { return notFound }
            return respond(url: url, status: 200, json: ["imports": serverFeatures.imports])

        case let (route, "DELETE") where route.hasPrefix("api/v1/migration/imports/"):
            guard aloha else { return notFound }
            let id = String(route.dropFirst("api/v1/migration/imports/".count))
            let before = serverFeatures.imports.count
            serverFeatures.imports.removeAll {
                ($0["id"] as? Int).map(String.init) == id && ($0["status"] as? String) == "done"
            }
            guard serverFeatures.imports.count < before else {
                return respond(
                    url: url, status: 404,
                    body:
                        #"{"error":"no finished import of yours has that id","code":"import-not-found"}"#
                )
            }
            return respond(url: url, status: 200, json: ["imports": serverFeatures.imports])

        case ("api/v1/migration/bookmarks", "POST"), ("api/v1/migration/domain_blocks", "POST"):
            guard aloha else { return notFound }
            let kind = String(route.dropFirst("api/v1/migration/".count))
            return respond(url: url, status: 202, json: ["import": queueImport(kind)])

        // MARK: Moving here
        case ("api/v1/migration/move-in/inspect", "POST"):
            guard aloha else { return notFound }
            let handle = form["handle"] ?? ""
            guard handle.contains("@") else {
                return respond(
                    url: url, status: 422, body: #"{"error":"that handle names nobody"}"#)
            }
            return respond(
                url: url, status: 200,
                json: [
                    "account": [
                        "id": "https://old.example/users/\(handle)", "acct": handle,
                        "name": "Old account", "url": "https://old.example/@\(handle)",
                        "avatar": "", "following": ["total": 42, "readable": true],
                        "posts": ["total": 300, "readable": false], "finishable": true,
                    ]
                ])

        case ("api/v1/migration/move-in", "POST"):
            guard aloha else { return notFound }
            return respond(url: url, status: 202, json: ["import": queueImport("move_in")])

        case ("api/v1/migration/move-in/finish", "POST"):
            guard aloha else { return notFound }
            return respond(
                url: url, status: 200,
                json: ["authorize_url": "https://old.example/oauth/authorize?client_id=mock"])

        case ("api/v1/migration/move-in/finish", "GET"):
            guard aloha else { return notFound }
            return respond(
                url: url, status: 200,
                json: ["status": "none", "acct": "", "at": 0, "error": ""])

        // MARK: Moving away (a Nextcloud session route)
        case ("api/v1/migration/move", "GET"):
            guard aloha else { return notFound }
            return respond(url: url, status: 200, json: moveStatus)

        case ("api/v1/migration/move", "POST"):
            guard aloha else { return notFound }
            guard form["confirm"]?.lowercased() == "alice@\(host)" else {
                return respond(
                    url: url, status: 422,
                    body:
                        #"{"error":"type your own handle to confirm the move","code":"confirm-handle"}"#
                )
            }
            serverFeatures.movedTo = "https://new.example/users/\(form["target"] ?? "")"
            serverFeatures.movedAt = Int(Date().timeIntervalSince1970)
            var answer = moveStatus
            answer["target"] = ["acct": form["target"] ?? "", "url": serverFeatures.movedTo ?? ""]
            return respond(url: url, status: 200, json: answer)

        case ("api/v1/migration/move", "DELETE"):
            guard aloha else { return notFound }
            serverFeatures.movedTo = nil
            return respond(url: url, status: 200, json: moveStatus)

        // MARK: Bluesky discovery
        case ("api/v1/social/bluesky/trends", "GET"):
            guard aloha else { return notFound }
            return respond(
                url: url, status: 200,
                json: [
                    "trends": [
                        [
                            "topic": "eclipse", "label": "Eclipse",
                            "feed": "at://did:plc:mock/app.bsky.feed.generator/eclipse",
                            "search": "",
                        ],
                        [
                            "topic": "election", "label": "Election", "feed": "",
                            "search": "election",
                        ],
                    ]
                ])

        case ("api/v1/social/bluesky/suggestions", "GET"):
            guard aloha else { return notFound }
            return respond(
                url: url, status: 200,
                json: [
                    "accounts": [
                        [
                            "id": "did:plc:suggested", "acct": "carol.bsky.social",
                            "username": "carol.bsky.social", "display_name": "Carol",
                            "avatar": "", "note": "Birds &amp; boats",
                            "url": "https://bsky.app/profile/carol.bsky.social",
                        ]
                    ]
                ])

        case ("api/v1/social/bluesky/starter-pack", "GET"):
            guard aloha else { return notFound }
            return respond(url: url, status: 200, json: ["pack": starterPack])

        case ("api/v1/social/bluesky/starter-pack/follow", "POST"):
            guard aloha else { return notFound }
            let dids = formArray(body, "dids")
            return respond(url: url, status: 200, json: ["followed": dids, "failed": []])

        case ("api/v1/social/bluesky/follow-from", "POST"):
            guard aloha else { return notFound }
            let account = form["account"] ?? ""
            return respond(
                url: url, status: 202,
                json: [
                    "import": queueImport("bluesky_follows"),
                    "account": ["did": "did:plc:\(account)", "handle": account],
                ])

        case ("api/v1/social/bluesky/handle", "POST"), ("api/v1/social/bluesky/handle", "DELETE"):
            guard aloha else { return notFound }
            serverFeatures.customHandle = method == "POST" ? form["handle"] ?? "" : ""
            return respond(
                url: url, status: 200,
                json: [
                    "handle": serverFeatures.customHandle.isEmpty
                        ? "alice.\(host)" : serverFeatures.customHandle,
                    "did": "did:plc:mockalice", "url": "https://bsky.app/profile/alice.\(host)",
                    "state": "active", "active": true, "recovery_key": false,
                    "assigned_handle": "alice.\(host)",
                    "custom_handle": serverFeatures.customHandle, "custom_handle_broken": false,
                ])

        // MARK: Smaller routes
        case ("api/v1/social/files_comments", "GET"), ("api/v1/social/files_comments", "PATCH"):
            guard aloha else { return notFound }
            if method == "PATCH" {
                let object = body.flatMap { try? JSONSerialization.jsonObject(with: $0) }
                guard let enabled = (object as? [String: Any])?["enabled"] as? Bool else {
                    return respond(
                        url: url, status: 422, body: #"{"error":"enabled must be true or false"}"#)
                }
                serverFeatures.filesComments = enabled
            }
            return respond(url: url, status: 200, json: ["enabled": serverFeatures.filesComments])

        case let (route, "GET")
        where route.hasPrefix("api/v1/statuses/") && route.hasSuffix("/reactions"):
            guard aloha else { return notFound }
            return respond(
                url: url, status: 200,
                json: [
                    ["name": "🎉", "count": 3, "me": true], ["name": "👀", "count": 1, "me": false],
                ])

        case ("api/v1/endorsements", "GET"):
            return respond(
                url: url, status: 200,
                json: [Fixtures.account(id: "2", username: "bob", host: host)])

        case let (route, method)
        where route.hasPrefix("api/v2/filters/") && route.hasSuffix("/statuses"):
            let filterID = route.dropFirst("api/v2/filters/".count).dropLast("/statuses".count)
            var entries = serverFeatures.filterStatuses[String(filterID)] ?? []
            if method == "POST" {
                serverFeatures.nextFilterStatusID += 1
                let entry: [String: Any] = [
                    "id": String(serverFeatures.nextFilterStatusID),
                    "status_id": form["status_id"] ?? "",
                ]
                entries.append(entry)
                serverFeatures.filterStatuses[String(filterID)] = entries
                return respond(url: url, status: 200, json: entry)
            }
            return respond(url: url, status: 200, json: entries)

        case let (route, "DELETE") where route.hasPrefix("api/v2/filters/statuses/"):
            let entryID = String(route.dropFirst("api/v2/filters/statuses/".count))
            for (filter, entries) in serverFeatures.filterStatuses {
                serverFeatures.filterStatuses[filter] = entries.filter {
                    ($0["id"] as? String) != entryID
                }
            }
            return respond(url: url, status: 200, body: "{}")

        default:
            return nil
        }
    }

    /// Queued and finished at once, so a test sees the report the run left.
    private func queueImport(_ kind: String) -> [String: Any] {
        serverFeatures.nextImportID += 1
        let stamp = ISO8601DateFormatter().string(from: Date())
        let job: [String: Any] = [
            "id": serverFeatures.nextImportID, "kind": kind, "status": "done", "total": 3,
            "done": 2, "skipped": 1, "failed": 0, "report": ["followed": 2, "skipped": 1],
            "options": [:], "created_at": stamp, "updated_at": stamp,
        ]
        serverFeatures.imports.insert(job, at: 0)
        return job
    }

    private var moveStatus: [String: Any] {
        [
            "moved_to": serverFeatures.movedTo ?? NSNull(),
            "moved_at": serverFeatures.movedTo == nil ? NSNull() : serverFeatures.movedAt,
            "can_move_at": serverFeatures.movedTo == nil ? 0 : serverFeatures.movedAt + 2_592_000,
        ]
    }

    private var starterPack: [String: Any] {
        [
            "uri": "at://did:plc:creator/app.bsky.graph.starterpack/mock",
            "url": "https://bsky.app/starter-pack/creator.bsky.social/mock",
            "name": "Sailing", "description": "People who sail.", "joined": 12,
            "creator": [
                "did": "did:plc:creator", "handle": "creator.bsky.social", "name": "Creator",
                "avatar": "",
            ],
            "members": [
                [
                    "did": "did:plc:one", "handle": "one.bsky.social", "name": "One",
                    "avatar": "", "description": "First", "following": false,
                ],
                [
                    "did": "did:plc:two", "handle": "two.bsky.social", "name": "Two",
                    "avatar": "", "description": "", "following": true,
                ],
            ],
            "feeds": [
                [
                    "uri": "at://did:plc:creator/app.bsky.feed.generator/sail", "type": "feed",
                    "name": "Sail", "description": "", "avatar": "",
                    "creator": "creator.bsky.social",
                ]
            ],
        ]
    }

    /// The values of `name[]` in a form body.
    private func formArray(_ body: Data?, _ name: String) -> [String] {
        guard let body, let text = String(data: body, encoding: .utf8) else { return [] }
        var components = URLComponents()
        components.percentEncodedQuery = text
        return (components.queryItems ?? []).filter { $0.name == "\(name)[]" }.compactMap(\.value)
    }
}
