// SPDX-License-Identifier: MIT

import AlohaModels
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A server that answers without a network, in any of the shapes the app has to
/// cope with (docs/12 §2).
///
/// Shipped in the library rather than the test target so the app's own debug
/// builds and previews can use it too.
public actor MockAPIServer: HTTPTransport {
    public enum Configuration: Sendable, Hashable {
        /// Routes at the domain root — PR #2250's rewrite rules applied.
        case nextcloudSocialWithRewrite
        /// Routes only under `/index.php/apps/social/`. **The most important
        /// configuration in the suite**: it is the difference between the app
        /// working for a self-hoster and not.
        case nextcloudSocialWithoutRewrite
        /// Stock Mastodon 4.3: streaming and Web Push advertised, none of the
        /// Nextcloud extensions present.
        case mastodon43
        /// Answers the Mastodon core and 404s every extension route.
        case coreOnly
        /// Answers 429 to everything.
        case rateLimited
        /// Signs in, then refuses every timeline. What a reader sees when the
        /// server is up but unwell.
        case timelinesUnavailable
        /// Serves a timeline whose third entry is malformed.
        case malformedEntities
    }

    public let configuration: Configuration
    public let host: String
    private(set) public var requestLog: [(method: String, path: String)] = []
    var statusFixtures: [[String: Any]]

    public init(
        configuration: Configuration,
        host: String = "cloud.example.test",
        statusCount: Int = 20
    ) {
        self.configuration = configuration
        self.host = host
        self.statusFixtures = (0..<statusCount).map { Fixtures.status(index: $0) }
    }

    public var loggedPaths: [String] { requestLog.map(\.path) }

    /// Where this configuration actually serves the Mastodon API.
    public var apiPrefix: String {
        switch configuration {
        case .nextcloudSocialWithoutRewrite: "/index.php/apps/social/"
        default: "/"
        }
    }

    private var isNextcloud: Bool {
        configuration == .nextcloudSocialWithRewrite
            || configuration == .nextcloudSocialWithoutRewrite
    }

    // MARK: - Transport

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw APIError.invalidResponse }

        // A request aimed at some other host does not reach this server at all.
        // Answering it anyway would let a discovery bug pass unnoticed.
        guard url.host()?.lowercased() == host.lowercased() else {
            throw APIError.transport(URLError(.cannotFindHost))
        }

        let method = request.httpMethod ?? "GET"
        requestLog.append((method, url.path()))

        if configuration == .rateLimited {
            return respond(url: url, status: 429, body: #"{"error":"Too many requests"}"#)
        }

        // NodeInfo and WebFinger are served at the true domain root whatever the
        // rewrite state — which is exactly what makes nodeinfo usable as the
        // cross-check in API base discovery.
        // Avatars, thumbnails and card images. Without these the tours never
        // exercise ImageLoader, its disk cache or the decode path, and every
        // screenshot shows a monogram or a blurhash.
        if let image = Self.imageResponse(for: url) {
            return respond(
                url: url, status: 200, data: image,
                headers: [
                    "Content-Type": "image/png"
                ])
        }

        if url.path().hasPrefix("/.well-known/nodeinfo") {
            return respond(url: url, status: 200, json: Fixtures.nodeInfo(nextcloud: isNextcloud))
        }

        guard let route = route(for: url) else {
            return respond(url: url, status: 404, body: #"{"error":"Not found"}"#)
        }
        return try answer(route: route, url: url, method: method, body: request.httpBody)
    }

    /// A plausible picture for any media-looking path, coloured by the path so
    /// two attachments never look like the same file.
    static func imageResponse(for url: URL) -> Data? {
        let path = url.path()
        let isImage =
            path.hasSuffix(".png") || path.hasSuffix(".jpg")
            || path.hasPrefix("/avatars/") || path.hasPrefix("/headers/")
        guard isImage else { return nil }

        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        let hue = Double(hash % 360) / 360
        let isAvatar = path.hasPrefix("/avatars/")
        let size = isAvatar ? 96 : 480
        let height = path.contains("_small") || isAvatar ? size : Int(Double(size) * 0.66)

        guard
            let context = CGContext(
                data: nil, width: size, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let top = colour(hue: hue, brightness: 0.85)
        let bottom = colour(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), brightness: 0.45)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top, bottom] as CFArray,
            locations: [0, 1])
        {
            context.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: size, y: height), options: [])
        }
        guard let image = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func colour(hue: Double, brightness: Double) -> CGColor {
        // A small HSB-to-RGB, so the mock needs no UI framework.
        let sector = hue * 6
        let index = Int(sector) % 6
        let fraction = sector - Double(Int(sector))
        let saturation = 0.55
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        let rgb: (Double, Double, Double)
        switch index {
        case 0: rgb = (brightness, t, p)
        case 1: rgb = (q, brightness, p)
        case 2: rgb = (p, brightness, t)
        case 3: rgb = (p, q, brightness)
        case 4: rgb = (t, p, brightness)
        default: rgb = (brightness, p, q)
        }
        return CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    func formFields(_ body: Data?) -> [String: String] {
        guard let body, let text = String(data: body, encoding: .utf8) else { return [:] }
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            return object.compactMapValues { $0 as? String }
        }
        var fields: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = parts.first?.removingPercentEncoding else { continue }
            fields[key] =
                (parts.count > 1 ? parts[1] : "")
                .replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
        }
        return fields
    }

    private var nextStatusID = 2000

    /// Strips the prefix this configuration serves under. A request to the root
    /// on a no-rewrite server finds nothing, which is the whole point.
    private func route(for url: URL) -> String? {
        let path = url.path()
        // OCS lives at the Nextcloud root whatever prefix the Social API is
        // served under, so it is matched before the prefix is stripped.
        if path.hasSuffix("/ocs/v2.php/cloud/capabilities") { return "ocs/capabilities" }
        guard path.hasPrefix(apiPrefix) else { return nil }
        var route = String(path.dropFirst(apiPrefix.count))
        if route.hasPrefix("/") { route.removeFirst() }
        return route
    }

    private func answer(
        route: String, url: URL, method: String, body: Data?
    ) throws -> (Data, HTTPURLResponse) {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch route {
        // MARK: Posting

        case "api/v1/statuses" where method == "POST":
            let fields = formFields(body)
            var status = Fixtures.status(index: 0, host: host)
            nextStatusID += 1
            status["id"] = String(nextStatusID)
            status["content"] = "<p>\(fields["status"] ?? "")</p>"
            status["spoiler_text"] = fields["spoiler_text"] ?? ""
            status["visibility"] = fields["visibility"] ?? "public"
            status["sensitive"] = false
            status["media_attachments"] = []
            status["favourites_count"] = 0
            status["reblogs_count"] = 0
            status["replies_count"] = 0
            status["account"] = Fixtures.account(id: "1", username: "alice", host: host)
            status["created_at"] = ISO8601DateFormatter().string(from: Date())
            if let reply = fields["in_reply_to_id"], !reply.isEmpty {
                status["in_reply_to_id"] = reply
                status["in_reply_to_account_id"] = "1"
            }
            statusFixtures.insert(status, at: 0)
            return respond(url: url, status: 200, json: status)

        // MARK: Discovery

        case "api/v2/search":
            let q = (query.first { $0.name == "q" }?.value ?? "").lowercased()
            let accounts = [("1", "alice"), ("2", "bob")]
                .filter { q.isEmpty || $0.1.contains(q) }
                .map { Fixtures.account(id: $0.0, username: $0.1, host: host) }
            let statuses = statusFixtures.prefix(6).filter {
                (($0["content"] as? String) ?? "").lowercased().contains(q)
            }
            let tags = ["nextcloud", "fediverse", "photography"].filter { $0.contains(q) }
            return respond(
                url: url, status: 200,
                json: [
                    "accounts": accounts, "statuses": Array(statuses),
                    "hashtags": tags.map { Fixtures.tag($0, host: host) },
                ])

        case "api/v1/trends/tags":
            return respond(
                url: url, status: 200,
                json: ["nextcloud", "fediverse", "photography", "opensource"]
                    .map { Fixtures.tag($0, host: host) })

        case "api/v1/trends/links":
            return respond(url: url, status: 200, json: [Fixtures.card(host: host)])

        case "api/v1/trends/statuses":
            return respond(url: url, status: 200, json: Array(statusFixtures.prefix(5)))

        case "api/v2/suggestions":
            return respond(
                url: url, status: 200,
                json: [
                    [
                        "source": "staff", "sources": ["featured"],
                        "account": Fixtures.account(id: "2", username: "bob", host: host),
                    ]
                ])

        case let route where route.hasPrefix("api/v1/tags/"):
            let name = String(
                route.dropFirst("api/v1/tags/".count).split(separator: "/").first ?? "")
            return respond(
                url: url, status: 200,
                json: Fixtures.tag(name, host: host, following: route.hasSuffix("/follow")))

        // MARK: Lists, conversations, saved

        case "api/v1/lists":
            if method == "POST" {
                let title = formFields(body)["title"] ?? "Untitled"
                return respond(
                    url: url, status: 200,
                    json: ["id": "9", "title": title, "replies_policy": "list", "exclusive": false])
            }
            return respond(
                url: url, status: 200,
                json: [
                    [
                        "id": "1", "title": "Colleagues", "replies_policy": "list",
                        "exclusive": false,
                    ],
                    [
                        "id": "2", "title": "Photographers", "replies_policy": "followed",
                        "exclusive": true,
                    ],
                ])

        case let route where route.hasPrefix("api/v1/lists/"):
            if route.hasSuffix("/accounts") {
                return respond(
                    url: url, status: 200,
                    json: [Fixtures.account(id: "2", username: "bob", host: host)])
            }
            return respond(
                url: url, status: 200,
                json: [
                    "id": "1", "title": "Colleagues", "replies_policy": "list", "exclusive": false,
                ])

        case "api/v1/followed_tags":
            return respond(
                url: url, status: 200,
                json: [Fixtures.tag("nextcloud", host: host, following: true)])

        case "api/v1/conversations":
            return respond(
                url: url, status: 200,
                json: [
                    [
                        "id": "c1", "unread": true,
                        "accounts": [Fixtures.account(id: "2", username: "bob", host: host)],
                        "last_status": statusFixtures[2],
                    ]
                ])

        case "api/v1/bookmarks", "api/v1/favourites", "api/v1/favourites/":
            return respond(url: url, status: 200, json: Array(statusFixtures.prefix(4)))

        case "api/v1/custom_emojis", "api/v1/announcements", "api/v1/scheduled_statuses",
            "api/v1/blocks", "api/v1/mutes", "api/v1/domain_blocks",
            "api/v1/notifications/requests":
            return respond(url: url, status: 200, body: "[]")

        case "api/v1/markers":
            return respond(url: url, status: 200, body: "{}")

        case let route where route.hasPrefix("api/v1/polls/"):
            var poll = Fixtures.poll()
            poll["voted"] = true
            poll["own_votes"] = [0]
            return respond(url: url, status: 200, json: poll)

        case "api/v2/instance":
            return respond(
                url: url, status: 200,
                json: Fixtures.instanceV2(
                    host: host, nextcloud: isNextcloud))

        case "api/v1/instance", "api/v1/instance/":
            return respond(
                url: url, status: 200,
                json: Fixtures.instanceV1(
                    host: host, nextcloud: isNextcloud))

        case ".well-known/oauth-authorization-server":
            let base = "https://\(host)\(apiPrefix)"
            return respond(
                url: url, status: 200,
                json: [
                    "authorization_endpoint": base + "oauth/authorize",
                    "token_endpoint": base + "oauth/token",
                    "revocation_endpoint": base + "oauth/revoke",
                    "code_challenge_methods_supported": ["S256"],
                ])

        case "api/v1/apps":
            return respond(
                url: url, status: 200,
                json: [
                    "id": "1",
                    "name": "Aloha Social",
                    "client_id": "mock-client-id",
                    "client_secret": "mock-client-secret",
                    "redirect_uri": OAuthService.redirectURI,
                    // Always present and always empty on Nextcloud Social.
                    "vapid_key": isNextcloud ? "" : "BNcTestVapidKey",
                ])

        case "oauth/token":
            return respond(
                url: url, status: 200,
                json: [
                    "access_token": "mock-access-token",
                    "token_type": "Bearer",
                    "scope": OAuthService.scopes,
                    "created_at": 1_758_326_400,
                ])

        case "oauth/revoke":
            return respond(url: url, status: 200, body: "{}")

        case "api/v1/accounts/verify_credentials":
            return respond(
                url: url, status: 200,
                json: Fixtures.account(
                    id: "1", username: "alice", host: host))

        case "api/v1/apps/verify_credentials":
            return respond(
                url: url, status: 200,
                json: [
                    "name": "Aloha Social", "website": OAuthService.website, "vapid_key": "",
                ])

        case "api/v1/preferences":
            return respond(
                url: url, status: 200,
                json: [
                    "posting:default:visibility": "public",
                    "posting:default:sensitive": false,
                    "posting:default:language": "en",
                    "reading:expand:media": "default",
                    "reading:expand:spoilers": false,
                ])

        // MARK: Timelines

        case let route where route.hasPrefix("api/v1/timelines/"):
            if configuration == .timelinesUnavailable {
                return respond(url: url, status: 429, body: #"{"error":"Too many requests"}"#)
            }
            return try timeline(url: url, route: route, query: query)

        // MARK: Extension routes

        case "api/v1/videos/continue", "api/v1/stories/carousel", "api/v1/collections":
            guard isNextcloud else {
                return respond(url: url, status: 404, body: #"{"error":"Not found"}"#)
            }
            return respond(url: url, status: 200, body: "[]")

        case "api/v1/media/from-file":
            guard isNextcloud else {
                return respond(url: url, status: 404, body: #"{"error":"Not found"}"#)
            }
            return respond(url: url, status: 405, body: #"{"error":"Method not allowed"}"#)

        case "api/v2/notifications", "api/v2/notifications/policy", "api/v2/filters":
            if configuration == .coreOnly {
                return respond(url: url, status: 404, body: #"{"error":"Not found"}"#)
            }
            if route == "api/v2/notifications" {
                return respond(
                    url: url, status: 200,
                    json: Fixtures.groupedNotifications(
                        statuses: Array(statusFixtures.prefix(3)), host: host))
            }
            let body = route == "api/v2/filters" ? "[]" : #"{"for_not_following":"accept"}"#
            return respond(url: url, status: 200, body: body)

        case "api/v1/notifications":
            return respond(
                url: url, status: 200,
                json: Fixtures.flatNotifications(
                    statuses: Array(statusFixtures.prefix(3)), host: host))

        case "api/v1/notifications/unread_count", "api/v2/notifications/unread_count":
            return respond(url: url, status: 200, body: #"{"count":3}"#)

        case "api/v1/accounts/relationships":
            let ids = query.filter { $0.name == "id[]" || $0.name == "id" }.compactMap(\.value)
            return respond(url: url, status: 200, json: ids.map { Fixtures.relationship(id: $0) })

        // MARK: Single status / account

        case let route where route.hasPrefix("api/v1/statuses/"):
            // The Nextcloud-only sub-routes (delivery, quotes, pin, dislike…)
            // answer from their own files and get first refusal.
            if let answered = extensionAnswer(
                route: route, url: url, method: method, query: query, body: body)
            {
                return answered
            }
            let parts = route.dropFirst("api/v1/statuses/".count).split(separator: "/")
            guard let id = parts.first.map(String.init),
                let status = statusFixtures.first(where: { ($0["id"] as? String) == id })
            else {
                return respond(url: url, status: 404, body: #"{"error":"Record not found"}"#)
            }
            switch parts.dropFirst().first {
            case nil:
                return respond(url: url, status: 200, json: status)
            case "context":
                // Two replies, so the thread has something below the fold.
                let replies = (1...2).map { offset -> [String: Any] in
                    var reply = Fixtures.status(index: 500 + offset, host: host)
                    reply["id"] = "\(id)-r\(offset)"
                    reply["in_reply_to_id"] = id
                    reply["in_reply_to_account_id"] = (status["account"] as? [String: Any])?["id"]
                    reply["content"] = "<p>Reply \(offset) to that.</p>"
                    reply["media_attachments"] = []
                    reply["spoiler_text"] = ""
                    return reply
                }
                return respond(
                    url: url, status: 200, json: ["ancestors": [], "descendants": replies])
            case "favourite", "unfavourite", "reblog", "unreblog", "bookmark", "unbookmark":
                var updated = status
                let action = String(parts[1])
                switch action {
                case "favourite":
                    updated["favourited"] = true
                    updated["favourites_count"] = ((status["favourites_count"] as? Int) ?? 0) + 1
                case "unfavourite":
                    updated["favourited"] = false
                    updated["favourites_count"] = max(
                        0, ((status["favourites_count"] as? Int) ?? 0) - 1)
                case "reblog":
                    updated["reblogged"] = true
                    updated["reblogs_count"] = ((status["reblogs_count"] as? Int) ?? 0) + 1
                case "unreblog":
                    updated["reblogged"] = false
                    updated["reblogs_count"] = max(0, ((status["reblogs_count"] as? Int) ?? 0) - 1)
                case "bookmark": updated["bookmarked"] = true
                default: updated["bookmarked"] = false
                }
                if let index = statusFixtures.firstIndex(where: { ($0["id"] as? String) == id }) {
                    statusFixtures[index] = updated
                }
                return respond(url: url, status: 200, json: updated)
            case "source":
                return respond(
                    url: url, status: 200,
                    json: [
                        "id": id,
                        "text": (status["content"] as? String ?? "")
                            .replacingOccurrences(
                                of: "<[^>]+>", with: "", options: .regularExpression),
                        "spoiler_text": status["spoiler_text"] as? String ?? "",
                    ])
            case "favourited_by", "reblogged_by":
                return respond(
                    url: url, status: 200,
                    json: [Fixtures.account(id: "2", username: "bob", host: host)])
            case "history":
                return respond(url: url, status: 200, body: "[]")
            case "translate":
                return respond(
                    url: url, status: 200,
                    json: [
                        "content": "<p>Testbeitrag mit einem Link.</p>", "spoiler_text": "",
                        "detected_source_language": "en", "provider": "Mock",
                    ])
            default:
                return respond(url: url, status: 404, body: #"{"error":"Not found"}"#)
            }

        case let route where route.hasPrefix("api/v1/accounts/"):
            // update_credentials, familiar_followers, highlights, notes and the
            // rest of the Nextcloud-only account routes answer from their own
            // files and get first refusal.
            if let answered = extensionAnswer(
                route: route, url: url, method: method, query: query, body: body)
            {
                return answered
            }
            let parts = route.dropFirst("api/v1/accounts/".count).split(separator: "/")
            guard let id = parts.first.map(String.init), ["1", "2"].contains(id) else {
                return respond(url: url, status: 404, body: #"{"error":"Record not found"}"#)
            }
            let username = id == "1" ? "alice" : "bob"
            switch parts.dropFirst().first {
            case nil:
                return respond(
                    url: url, status: 200,
                    json: Fixtures.account(
                        id: id, username: username, host: host))
            case "statuses":
                let own = statusFixtures.filter {
                    (($0["account"] as? [String: Any])?["id"] as? String) == id
                }
                return respond(url: url, status: 200, json: Array(own.prefix(20)))
            case "followers", "following":
                return respond(url: url, status: 200, body: "[]")
            default:
                return respond(url: url, status: 404, body: #"{"error":"Not found"}"#)
            }

        case "api/v1/instance/translation_languages":
            return respond(
                url: url, status: 200, json: isNextcloud ? ["de": ["en"], "en": ["de"]] : [:])

        default:
            // The Nextcloud-only surfaces each answer from their own file.
            if let answered = extensionAnswer(
                route: route, url: url, method: method, query: query, body: body)
            {
                return answered
            }
            return respond(url: url, status: 404, body: #"{"error":"Not found"}"#)
        }
    }

    private func timeline(
        url: URL, route: String, query: [URLQueryItem]
    ) throws -> (Data, HTTPURLResponse) {
        // Nextcloud Social answers 422 for a {timeline} it does not know; only
        // it accepts the three narrowings.
        let onlyVideo = query.first { $0.name == "only_video" }?.value == "true"
        let onlyNews = query.first { $0.name == "only_news" }?.value == "true"
        if (onlyVideo || onlyNews) && !isNextcloud {
            return respond(url: url, status: 422, body: #"{"error":"Unknown parameter"}"#)
        }

        let limit = Int(query.first { $0.name == "limit" }?.value ?? "") ?? 20
        let maxID = query.first { $0.name == "max_id" }?.value
        let minID = query.first { $0.name == "min_id" }?.value

        // Each of the three timelines says which one it is. Without this the
        // fixtures are identical and a switch is indistinguishable from a
        // switch that did nothing — which is how a broken source picker
        // survived every tour.
        let segment =
            route.contains("/public")
            ? (query.first { $0.name == "local" }?.value == "true" ? "Local" : "Global") : "Home"

        var rows = statusFixtures.map { row -> [String: Any] in
            guard segment != "Home" else { return row }
            // Only the words change. Clearing the attachments too left Shorts
            // with nothing to play.
            var copy = row
            let index = row["id"] as? String ?? ""
            copy["content"] = "<p>\(segment) timeline post \(index).</p>"
            return copy
        }
        if let maxID, let cutoff = Int(maxID) {
            rows = rows.filter { Int($0["id"] as? String ?? "") ?? 0 < cutoff }
        }
        if let minID, let cutoff = Int(minID) {
            rows = rows.filter { Int($0["id"] as? String ?? "") ?? 0 > cutoff }
        }
        let onlyMedia = query.first { $0.name == "only_media" }?.value == "true"
        if onlyMedia {
            rows = rows.filter { !(($0["media_attachments"] as? [[String: Any]]) ?? []).isEmpty }
        }
        if onlyVideo {
            rows = rows.filter { row in
                let media = row["media_attachments"] as? [[String: Any]] ?? []
                return media.contains { ($0["type"] as? String) == "video" }
            }
        }
        let page = Array(rows.prefix(limit))

        var payload: [Any] = page
        if configuration == .malformedEntities, payload.count > 2 {
            payload[2] = ["id": "malformed", "this_is_not": "a status"]
        }

        var headers: [String: String] = [:]
        // `next` is sent only while a further page may exist; a page shorter
        // than `limit` is the last one.
        if page.count >= limit, let last = page.last?["id"] as? String {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems =
                (components.queryItems ?? [])
                .filter { $0.name != "max_id" && $0.name != "min_id" }
                + [URLQueryItem(name: "max_id", value: last)]
            headers["Link"] = "<\(components.url!.absoluteString)>; rel=\"next\""
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        return respond(url: url, status: 200, data: data, headers: headers)
    }

    // MARK: - Responses

    func respond(
        url: URL, status: Int, body: String = "", headers: [String: String] = [:]
    ) -> (Data, HTTPURLResponse) {
        respond(url: url, status: status, data: Data(body.utf8), headers: headers)
    }

    func respond(
        url: URL, status: Int, json: Any, headers: [String: String] = [:]
    ) -> (Data, HTTPURLResponse) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        return respond(url: url, status: status, data: data, headers: headers)
    }

    func respond(
        url: URL, status: Int, data: Data, headers: [String: String] = [:]
    ) -> (Data, HTTPURLResponse) {
        var allHeaders = headers
        allHeaders["Content-Type"] = "application/json"
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: allHeaders)!
        return (data, response)
    }
}

/// JSON shaped the way the real servers shape it, including the awkward parts.
public enum Fixtures {
    public static func nodeInfo(nextcloud: Bool) -> [String: Any] {
        [
            "version": "2.1",
            "software": [
                "name": nextcloud ? "Nextcloud Social" : "mastodon",
                "version": nextcloud ? "0.24.1" : "4.3.2",
            ],
            "protocols": ["activitypub"],
            "openRegistrations": false,
        ]
    }

    public static func instanceV2(host: String, nextcloud: Bool) -> [String: Any] {
        var configuration: [String: Any] = [
            "statuses": [
                "max_characters": nextcloud ? 5000 : 500,
                "max_media_attachments": 4,
                "characters_reserved_per_url": 23,
            ],
            "media_attachments": [
                "supported_mime_types": ["image/jpeg", "image/png", "video/mp4", "audio/mpeg"],
                "image_size_limit": 10 * 1024 * 1024,
                "video_size_limit": 2048 * 1024 * 1024,
            ],
            "polls": [
                "max_options": 4, "max_characters_per_option": 50,
                "min_expiration": 300, "max_expiration": 2_629_746,
            ],
            "translation": ["enabled": nextcloud],
        ]
        // Nextcloud Social sends an empty urls object and an empty vapid key:
        // both are deliberate signals meaning "do not wait, do not offer".
        configuration["urls"] =
            nextcloud
            ? [:] : ["streaming_api": "wss://\(host)/api/v1/streaming"]
        configuration["vapid"] = ["public_key": nextcloud ? "" : "BNcTestVapidKey"]

        return [
            "domain": host,
            "title": nextcloud ? "Example Nextcloud" : "Example Mastodon",
            "version": nextcloud
                ? "4.2.0 (compatible; Nextcloud Social 0.24.1)" : "4.3.2",
            "description": "A test instance.",
            "thumbnail": ["url": "https://\(host)/thumbnail.png"],
            "languages": ["en"],
            "rules": [["id": "1", "text": "Be kind."]],
            "registrations": ["enabled": false, "approval_required": false],
            "contact": ["email": "admin@\(host)"],
            "api_versions": ["mastodon": 3],
            "configuration": configuration,
        ]
    }

    public static func instanceV1(host: String, nextcloud: Bool) -> [String: Any] {
        var payload = instanceV2(host: host, nextcloud: nextcloud)
        payload["uri"] = host
        payload.removeValue(forKey: "domain")
        payload["thumbnail"] = "https://\(host)/thumbnail.png"
        payload["short_description"] = "A test instance."
        payload["urls"] = nextcloud ? [:] : ["streaming_api": "wss://\(host)/api/v1/streaming"]
        payload["stats"] = ["user_count": 42, "status_count": 1234, "domain_count": 99]
        payload["registrations"] = false
        payload["approval_required"] = false
        return payload
    }

    public static func account(id: String, username: String, host: String) -> [String: Any] {
        [
            "id": id,
            "username": username,
            "acct": username,
            "display_name": username.capitalized,
            "note": "<p>A test account.</p>",
            "url": "https://\(host)/@\(username)",
            // Deliberately empty: Nextcloud Social can send "" here, and a
            // decoder that insists on a URL fails the whole account.
            "avatar": id == "2" ? "" : "https://\(host)/avatars/\(username).png",
            "header": "https://\(host)/headers/\(username).png",
            "locked": false,
            "bot": false,
            "created_at": "2024-01-01T00:00:00.000Z",
            "followers_count": 120,
            "following_count": 80,
            "statuses_count": 400,
            "fields": [],
            "emojis": [],
        ]
    }

    /// Ids descend so that `max_id` paging behaves like a real timeline.
    public static func relationship(id: String) -> [String: Any] {
        [
            "id": id, "following": id == "2", "followed_by": id == "2", "blocking": false,
            "muting": false, "muting_notifications": false, "requested": false,
            "domain_blocking": false, "endorsed": false, "note": "",
            "showing_reblogs": true, "notifying": false,
        ]
    }

    public static func flatNotifications(statuses: [[String: Any]], host: String) -> [[String: Any]]
    {
        let kinds = ["favourite", "reblog", "mention"]
        return statuses.enumerated().map { offset, status in
            [
                "id": String(9000 - offset),
                "type": kinds[offset % kinds.count],
                "created_at": "2026-09-20T12:0\(offset):00.000Z",
                "account": account(id: "2", username: "bob", host: host),
                "status": status,
            ]
        }
    }

    public static func groupedNotifications(
        statuses: [[String: Any]], host: String
    ) -> [String: Any] {
        let kinds = ["favourite", "reblog", "mention"]
        let groups: [[String: Any]] = statuses.enumerated().map { offset, status in
            [
                "group_key": "\(kinds[offset % kinds.count])-\(status["id"] as? String ?? "")",
                "notifications_count": offset + 1,
                "type": kinds[offset % kinds.count],
                "most_recent_notification_id": String(9000 - offset),
                "page_min_id": String(9000 - offset),
                "page_max_id": String(9000 - offset),
                "latest_page_notification_at": "2026-09-20T12:0\(offset):00.000Z",
                "sample_account_ids": ["2"],
                "status_id": status["id"] as? String ?? "",
            ]
        }
        return [
            "accounts": [account(id: "2", username: "bob", host: host)],
            "statuses": statuses,
            "notification_groups": groups,
        ]
    }

    public static func tag(_ name: String, host: String, following: Bool = false) -> [String: Any] {
        var history: [[String: String]] = []
        for day in 0..<7 {
            let stamp: Int = 1_758_000_000 - day * 86400
            let uses: Int = 40 - day * 3
            let accounts: Int = 20 - day
            history.append([
                "day": String(stamp), "uses": String(uses), "accounts": String(accounts),
            ])
        }
        return [
            "name": name, "url": "https://\(host)/tags/\(name)", "following": following,
            "history": history,
        ]
    }

    public static func card(host: String) -> [String: Any] {
        [
            "url": "https://nextcloud.com/blog/", "title": "Nextcloud Hub 12 is here",
            "description": "Everything new in the release, in one place.", "type": "link",
            "author_name": "Nextcloud", "provider_name": "nextcloud.com",
            "image": "https://\(host)/media/card.jpg", "blurhash": "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
            "width": 1200, "height": 630,
        ]
    }

    public static func poll() -> [String: Any] {
        [
            "id": "p1", "expires_at": "2026-12-31T00:00:00.000Z", "expired": false,
            "multiple": false, "votes_count": 12, "voters_count": 12, "voted": false,
            "own_votes": [],
            "options": [
                ["title": "Nextcloud Social", "votes_count": 7],
                ["title": "Mastodon", "votes_count": 3],
                ["title": "Both, on the same client", "votes_count": 2],
            ],
            "emojis": [],
        ]
    }

    public static func status(index: Int, host: String = "cloud.example.test") -> [String: Any] {
        let id = String(1000 - index)
        let isVideo = index % 4 == 1
        let isPhoto = index % 4 == 2
        let hasPoll = index == 3
        let hasCard = index == 4
        let isBoost = index == 6
        let isReply = index == 8
        let mentionsBob = index == 3
        let hasTag = index == 4

        var media: [[String: Any]] = []
        if isVideo {
            media = [
                [
                    "id": "m\(id)",
                    "type": "video",
                    "url": "https://\(host)/media/\(id).mp4",
                    "preview_url": "https://\(host)/media/\(id).jpg",
                    "remote_url": NSNull(),
                    "description": "A test video.",
                    "blurhash": "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
                    "meta": ["original": ["width": 1080, "height": 1920, "duration": 22.5]],
                    // Nextcloud Social's own key, alongside Mastodon's.
                    "hls_url": "https://\(host)/media/hls/\(id)/master.m3u8",
                ]
            ]
        } else if isPhoto {
            media = [
                [
                    "id": "m\(id)",
                    "type": "image",
                    "url": "https://\(host)/media/\(id).jpg",
                    "preview_url": "https://\(host)/media/\(id)_small.jpg",
                    "remote_url": NSNull(),
                    "description": "A test photograph.",
                    "blurhash": "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
                    "meta": ["original": ["width": 1600, "height": 1200]],
                ]
            ]
        }

        var base: [String: Any] = [
            "id": id,
            "uri": "https://\(host)/statuses/\(id)",
            "url": "https://\(host)/@alice/\(id)",
            "created_at": "2026-09-20T10:\(String(format: "%02d", index % 60)):00.000Z",
            "edited_at": NSNull(),
            "content": Self.content(
                index: index, host: host, mentionsBob: mentionsBob, hasTag: hasTag),
            "spoiler_text": index % 7 == 0 ? "Testing" : "",
            "visibility": "public",
            "sensitive": index % 9 == 0,
            "language": "en",
            "account": account(
                id: index % 5 == 0 ? "2" : "1", username: index % 5 == 0 ? "bob" : "alice",
                host: host),
            "replies_count": index % 5,
            "reblogs_count": index % 3,
            "favourites_count": index,
            "favourited": false,
            "reblogged": false,
            "bookmarked": false,
            "pinned": false,
            "muted": false,
            "in_reply_to_id": isReply ? "1000" : NSNull(),
            "in_reply_to_account_id": isReply ? "2" : NSNull(),
            "media_attachments": media,
            "mentions": mentionsBob
                ? [["id": "2", "username": "bob", "acct": "bob", "url": "https://\(host)/@bob"]]
                : [],
            "tags": hasTag ? [["name": "nextcloud", "url": "https://\(host)/tags/nextcloud"]] : [],
            "emojis": [],
            "poll": hasPoll ? poll() : NSNull(),
            "card": hasCard ? card(host: host) : NSNull(),
        ]
        if isVideo {
            // What a PeerTube-origin video carries on Nextcloud Social.
            base["video"] = [
                "views": 1234, "likes": 12, "dislikes": 1,
                "category": "Science & Technology", "language": "en", "licence": "CC BY 4.0",
                "live": false, "support": "Buy me a coffee", "download": true,
                "chapters": [
                    ["start": 0, "title": "Intro"],
                    ["start": 8, "title": "The demo"],
                    ["start": 17, "title": "Wrap-up"],
                ],
            ]
            base["dislikes_count"] = 1
            base["disliked"] = false
        }
        if isBoost {
            // Bob boosting Alice's post: the row shows a context line and the
            // boosted status, not the wrapper.
            var inner = base
            inner["id"] = "b\(id)"
            inner["account"] = account(id: "1", username: "alice", host: host)
            inner["content"] = "<p>The post Bob boosted.</p>"
            inner["media_attachments"] = []
            inner["spoiler_text"] = ""
            base["reblog"] = inner
            base["content"] = ""
            base["media_attachments"] = []
            base["spoiler_text"] = ""
            base["account"] = account(id: "2", username: "bob", host: host)
        }
        return base
    }

    private static func content(index: Int, host: String, mentionsBob: Bool, hasTag: Bool) -> String
    {
        var text = "Test post number \(index) with a <a href=\"https://example.test\">link</a>."
        if mentionsBob {
            text =
                "<span class=\"h-card\"><a href=\"https://\(host)/@bob\" class=\"u-url mention\">@<span>bob</span></a></span> which one do you use? "
                + text
        }
        if hasTag {
            text +=
                " <a href=\"https://\(host)/tags/nextcloud\" class=\"mention hashtag\" rel=\"tag\">#<span>nextcloud</span></a>"
        }
        return "<p>\(text)</p>"
    }

}
