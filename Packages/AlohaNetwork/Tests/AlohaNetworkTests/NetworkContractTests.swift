// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

/// Records what goes on the wire and answers with whatever it was given.
private actor RecordingTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var status: Int
    private var body: Data
    private var headers: [String: String]

    init(status: Int = 200, body: String = "{}", headers: [String: String] = [:]) {
        self.status = status
        self.body = Data(body.utf8)
        self.headers = headers
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url ?? URL(fileURLWithPath: "/")
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        guard let response else { throw APIError.invalidResponse }
        return (body, response)
    }
}

private let base = URL(string: "https://cloud.example.test/")!

private func client(_ transport: RecordingTransport) -> APIClient {
    APIClient(accountID: UUID(), apiBase: base, accessToken: "secret", transport: transport)
}

/// Decodes a form body the way PHP does: `+` is a space, `%XX` is a byte.
private func parsedForm(_ data: Data?) -> [String: String] {
    let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
    var fields: [String: String] = [:]
    for pair in text.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map {
            String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
        }
        if parts.count == 2 { fields[parts[0]] = parts[1] }
    }
    return fields
}

private func formValue(_ endpoint: Endpoint, _ name: String) -> String? {
    guard case .form(let items) = endpoint.body else { return nil }
    return items.first { $0.name == name }?.value
}

// MARK: - Idea 2: form encoding

@Suite("Form encoding")
struct FormEncodingTests {

    @Test("Everything outside RFC 3986's unreserved set is escaped")
    func escapesReservedCharacters() {
        #expect(FormEncoding.escape("+&=%;") == "%2B%26%3D%25%3B")
        #expect(FormEncoding.escape("a b") == "a%20b")
        #expect(FormEncoding.escape("Az09-._~") == "Az09-._~")
        #expect(FormEncoding.escape("Grüße 🌺") == "Gr%C3%BC%C3%9Fe%20%F0%9F%8C%BA")
    }

    @Test("Items without a value are left out, as queries leave them")
    func skipsNilValues() {
        let encoded = FormEncoding.encode([
            URLQueryItem(name: "status", value: "C++"),
            URLQueryItem(name: "spoiler_text", value: nil),
            URLQueryItem(name: "media_ids[]", value: "1"),
        ])
        #expect(encoded == "status=C%2B%2B&media_ids%5B%5D=1")
    }

    @Test("A post saying C++ and 1+1=2 arrives as written, not as spaces")
    func postBodyRoundTrips() async throws {
        let transport = RecordingTransport(body: #"{"id":"1"}"#)
        let text = "C++ & 1+1=2; 100% sure 🌺"
        _ = try await client(transport).send(
            Endpoint(
                method: .post, path: "api/v1/statuses",
                body: .form([
                    URLQueryItem(name: "status", value: text)
                ])))
        let request = try #require(await transport.requests.first)
        #expect(parsedForm(request.httpBody)["status"] == text)
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")
                == "application/x-www-form-urlencoded; charset=utf-8")
    }

    @Test("A + in a query is a plus sign, not a space")
    func queryKeepsPlus() throws {
        let url = try #require(
            Endpoint(path: "api/v2/search", query: [URLQueryItem(name: "q", value: "C++")])
                .url(base: base))
        #expect(url.absoluteString == "https://cloud.example.test/api/v2/search?q=C%2B%2B")
    }

    @Test("The push registration's base64 keys survive the form body")
    func base64Survives() {
        let key = "MIIBIjANBgkqh+kiG9w0BAQEFAAOCAQ8A/MIIBCgKCAQEA=="
        let body = FormEncoding.body([URLQueryItem(name: "devicePublicKey", value: key)])
        #expect(parsedForm(body)["devicePublicKey"] == key)
    }
}

// MARK: - Idea 10: credentials stay on the account's origin

@Suite("Credential origin")
struct CredentialOriginTests {

    @Test("A Link cursor to another host is refused, and nothing is sent")
    func refusesForeignCursor() async throws {
        let transport = RecordingTransport(body: "[]")
        let api = client(transport)
        await #expect(throws: APIError.self) {
            _ = try await api.page(
                LossyArray<Status>.self,
                following: URL(string: "https://evil.example/api/v1/timelines/home?max_id=1")!,
                limit: 20)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("A cursor on the same host carries the token")
    func followsOwnCursor() async throws {
        let transport = RecordingTransport(body: "[]")
        _ = try await client(transport).page(
            LossyArray<Status>.self,
            following: URL(string: "https://cloud.example.test/api/v1/timelines/home?max_id=1")!,
            limit: 20)
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test("An http cursor on the account's own https host is followed over https")
    func upgradesOwnHTTPCursor() async throws {
        let transport = RecordingTransport(body: "[]")
        _ = try await client(transport).page(
            LossyArray<Status>.self,
            following: URL(string: "http://cloud.example.test/api/v1/favourites?max_id=9")!,
            limit: 20)
        let request = try #require(await transport.requests.first)
        #expect(request.url?.scheme == "https")
        #expect(request.url?.host() == "cloud.example.test")
    }
}

// MARK: - Idea 11: the rate limiter

@Suite("Rate limiter")
struct RateLimiterTests {

    @Test("A long 429 block fails at once instead of holding the request")
    func longBlockFailsFast() async {
        let limiter = RateLimiter()
        await limiter.noteRateLimited(host: "cloud.example.test", retryAfter: 120)
        do {
            try await limiter.acquire(host: "cloud.example.test")
            Issue.record("expected .rateLimited")
        } catch let APIError.rateLimited(retryAfter) {
            #expect((retryAfter ?? 0) > 100)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test("A cancelled wait throws instead of spinning until the block passes")
    func cancellationStopsTheWait() async {
        let limiter = RateLimiter()
        await limiter.noteRateLimited(host: "cloud.example.test", retryAfter: 5)
        let started = Date()
        let task = Task { try await limiter.acquire(host: "cloud.example.test") }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let result = await task.result
        #expect(Date().timeIntervalSince(started) < 2)
        guard case .failure(let error) = result, case APIError.cancelled = error else {
            Issue.record("expected .cancelled, got \(result)")
            return
        }
    }

    @Test("Retry-After is read whatever its case, and as an HTTP-date")
    func retryAfterForms() {
        #expect(APIError.retryAfter(in: ["retry-after": "30"]) == 30)
        #expect(APIError.retryAfter(in: ["RETRY-AFTER": " 12 "]) == 12)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let later = "Fri, 15 Jan 2027 08:00:30 GMT"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let expected = formatter.date(from: later).map { $0.timeIntervalSince(now) }
        #expect(APIError.retryAfter(in: ["Retry-After": later], now: now) == expected)
        #expect(APIError.retryAfter(in: ["Retry-After": "soon"]) == nil)
    }
}

// MARK: - Idea 8: refusal codes and server messages

@Suite("Refusal codes")
struct RefusalCodeTests {

    @Test("A coded 422 says the app's own sentence, with the server's limit")
    func featuredTagsFull() throws {
        let body = Data(
            #"{"error":"Limit of 4 featured tags reached","code":"featured-tags-full","limit":4}"#
                .utf8)
        guard
            case .unprocessable(let message)? = APIError.from(status: 422, data: body, headers: [:])
        else {
            Issue.record("expected .unprocessable")
            return
        }
        #expect(message.contains("4"))
        #expect(message != "Limit of 4 featured tags reached")
    }

    @Test("A 409 import-running keeps its code and reads as advice")
    func importRunning() throws {
        let body = Data(#"{"error":"An import is running","code":"import-running"}"#.utf8)
        let error = try #require(APIError.from(status: 409, data: body, headers: [:]))
        #expect(error.refusalCode == "import-running")
        #expect(error.errorDescription?.contains("409") == false)
    }

    @Test("An unknown code falls back to the server's sentence")
    func unknownCodeFallsBack() throws {
        let body = Data(#"{"error":"Something new","code":"brand-new-code","max":3}"#.utf8)
        let error = try #require(APIError.from(status: 413, data: body, headers: [:]))
        guard case .refused(let refusal) = error else {
            Issue.record("expected .refused")
            return
        }
        #expect(refusal.parameters["max"] == "3")
        #expect(error.errorDescription == "Something new")
    }

    @Test("A 404 keeps the server's reason, and still matches .notFound")
    func notFoundKeepsMessage() throws {
        let body = Data(#"{"error":"Bluesky is not enabled on this server"}"#.utf8)
        let error = try #require(APIError.from(status: 404, data: body, headers: [:]))
        guard case .notFound = error else {
            Issue.record("expected .notFound")
            return
        }
        #expect(error.errorDescription == "Bluesky is not enabled on this server")
    }

    @Test("A 400's message is shown; a 5xx's fixed sentence is not")
    func messagesByStatus() throws {
        let bad = try #require(
            APIError.from(status: 400, data: Data(#"{"message":"Bad poll"}"#.utf8), headers: [:]))
        #expect(bad.errorDescription == "Bad poll")
        let broken = try #require(
            APIError.from(
                status: 500, data: Data(#"{"error":"Something went wrong on this server"}"#.utf8),
                headers: [:]))
        #expect(broken.errorDescription?.contains("500") == true)
        let page = try #require(
            APIError.from(status: 403, data: Data("<html>Forbidden</html>".utf8), headers: [:]))
        #expect(page.errorDescription?.contains("<html>") == false)
    }

    @Test("The Bluesky probe tells account-not-set-up apart from Bluesky being off")
    func blueskyProbeNotSetUp() async {
        let transport = RecordingTransport(
            status: 403,
            body:
                #"{"error":"Set up your account","code":"account-not-set-up","setup_url":"https://cloud.example.test/apps/social/setup"}"#
        )
        let api = client(transport)
        await api.updateNextcloudAuthorization("Basic eDp5")
        let availability = await BlueskyAvailability.probe(api)
        #expect(
            availability
                == .accountNotSetUp(
                    setupURL: URL(string: "https://cloud.example.test/apps/social/setup")))
        #expect(availability.isAvailable == false)
    }
}

// MARK: - Idea 4: the server's own field names

@Suite("Server field names")
struct ServerFieldNameTests {

    @Test("Reactions name the emoji as the server reads it")
    func reactionParameter() {
        #expect(formValue(Endpoint.statuses.react("7", emoji: "🌺"), "emoji") == "🌺")
        #expect(formValue(Endpoint.statuses.unreact("7", emoji: "🌺"), "emoji") == "🌺")
        #expect(formValue(Endpoint.statuses.react("7", emoji: "🌺"), "name") == nil)
    }

    @Test("The media preference is expand_media")
    func expandMedia() {
        #expect(
            formValue(Endpoint.instance.setExpandMedia("hide_all"), "expand_media") == "hide_all")
    }

    @Test("A place's longitude is decoded from long, as strings")
    func placeLongitude() throws {
        let json = Data(
            #"{"id":"5","name":"Berlin","country":"Germany","lat":"52.52","long":"13.405"}"#.utf8)
        let place = try AlohaJSON.decoder.decode(Place.self, from: json)
        #expect(place.latitude == 52.52)
        #expect(place.longitude == 13.405)
        let tagged = try AlohaJSON.decoder.decode(Status.StatusPlace.self, from: json)
        #expect(tagged.longitude == 13.405)
        // What an older build cached still reads.
        let legacy = Data(#"{"id":"5","name":"Berlin","lat":52.5,"lon":13.4}"#.utf8)
        #expect(try AlohaJSON.decoder.decode(Place.self, from: legacy).longitude == 13.4)
    }

    @Test("quote_approval sets the policy, and current_user denied disables quoting")
    func quoteApproval() throws {
        var fixture = Fixtures.status(index: 1)
        fixture["quote_approval"] = [
            "automatic": ["followers"], "manual": [], "current_user": "denied",
        ]
        fixture["interaction_policy"] = ["reply": false]
        let data = try JSONSerialization.data(withJSONObject: fixture)
        let status = try AlohaJSON.decoder.decode(Status.self, from: data)
        #expect(status.quoteApprovalPolicy == "followers")
        #expect(status.viewerMayQuote == false)
        #expect(status.interactionAllowed("reply") == false)
        #expect(status.interactionAllowed("like") == nil)

        var nobody = Fixtures.status(index: 2)
        nobody["quote_approval"] = ["automatic": [], "manual": [], "current_user": "automatic"]
        let open = try AlohaJSON.decoder.decode(
            Status.self, from: JSONSerialization.data(withJSONObject: nobody))
        #expect(open.quoteApprovalPolicy == "nobody")
        #expect(open.viewerMayQuote == true)
    }

    @Test("Favourites and bookmarks page only by the server's cursor")
    func markPagedSources() {
        #expect(TimelineSource.favourites.pagesOnlyByLink)
        #expect(TimelineSource.bookmarks.pagesOnlyByLink)
        #expect(!TimelineSource.home.pagesOnlyByLink)
    }
}

// MARK: - Idea 5: session-only routes and the migration kinds

@Suite("Session routes")
struct SessionRouteTests {

    @Test("Routes the server keeps for a Nextcloud session carry the app password")
    func sessionRoutes() {
        let routes: [Endpoint] = [
            .media.fromNextcloudFile(path: "/Photos/a.jpg", description: nil),
            .review.held, .review.withdraw("3"),
            .migration.aliases, .migration.addAlias("@a@b.example"),
            .migration.removeAlias("@a@b.example"), .migration.announcement,
            .migration.findPeople(["@a@b.example"]),
            .migration.instagramPeople(Data(), filename: "a.zip"),
        ]
        for route in routes {
            #expect(route.authentication == .nextcloudSession, "\(route.path)")
        }
    }

    @Test("Followers can be exported but not imported; bookmarks and blocked servers both")
    func listKinds() {
        #expect(Endpoint.migration.importList(.followers, csv: Data(), filename: "f.csv") == nil)
        #expect(
            Endpoint.migration.importList(.bookmarks, csv: Data(), filename: "b.csv")?.path
                == "api/v1/migration/bookmarks")
        #expect(
            Endpoint.migration.importList(.domainBlocks, csv: Data(), filename: "d.csv")?.path
                == "api/v1/migration/domain_blocks")
        #expect(
            Endpoint.migration.exportList(.domainBlocks).path
                == "api/v1/migration/export/domain_blocks")
        #expect(!Endpoint.migration.ListKind.importable.contains(.followers))
    }
}

// MARK: - Idea 7: the server's own notification types

@Suite("Aloha notification types")
struct AlohaNotificationTypeTests {

    @Test("On Aloha Social every drawn type is named, the first-party ones included")
    func everyTypeOnAloha() {
        let types = Endpoint.notifications.everyType(onAlohaSocial: true)
        #expect(types.contains("mention"))
        #expect(types.contains("story:react"))
        #expect(types.contains("bluesky:starterpack_joined"))
        #expect(Endpoint.notifications.everyType(onAlohaSocial: false).isEmpty)
    }

    @Test("They reach the query as types[]")
    func reachesQuery() throws {
        let endpoint = Endpoint.notifications.grouped(
            types: Endpoint.notifications.everyType(onAlohaSocial: true))
        let url = try #require(endpoint.url(base: base))
        #expect(url.absoluteString.contains("types%5B%5D=story%3Areact"))
    }

    @Test("Each decodes as its own kind, not as unknown")
    func decodes() throws {
        for raw in ["story:react", "story:comment", "tagged", "bluesky:verified"] {
            let kind = try JSONDecoder().decode(
                NotificationKind.self, from: Data("\"\(raw)\"".utf8))
            #expect(kind.rawValue == raw)
            #expect(!kind.isUnknown)
        }
    }
}

// MARK: - Idea 10: cleartext only on the local network

@Suite("Local network")
struct LocalNetworkTests {

    @Test("Private, link-local, loopback and .local hosts are local; public ones are not")
    func classification() {
        for host in [
            "192.168.1.10", "10.0.0.2", "172.20.1.1", "169.254.3.4", "127.0.0.1", "100.64.0.1",
            "nas.local", "localhost", "cloud", "[::1]", "fe80::1", "fd12:3456::1",
        ] {
            #expect(LocalNetwork.isLocal(host: host), "\(host)")
        }
        for host in ["cloud.example.com", "8.8.8.8", "172.32.0.1", "100.128.0.1", "2001:db8::1"] {
            #expect(!LocalNetwork.isLocal(host: host), "\(host)")
        }
    }

    @Test("Media on a public host is asked for over https; on the local network it stays")
    func securedForLoading() {
        #expect(
            URL(string: "http://files.example.com/a.jpg")!.securedForLoading.absoluteString
                == "https://files.example.com/a.jpg")
        #expect(
            URL(string: "http://192.168.1.10:8080/a.jpg")!.securedForLoading.absoluteString
                == "http://192.168.1.10:8080/a.jpg")
        #expect(
            URL(string: "https://files.example.com/a.jpg")!.securedForLoading.absoluteString
                == "https://files.example.com/a.jpg")
    }

    @Test("Sign-in asks a public http server over https, a local one as typed")
    func signInAddress() {
        let publicServer = ServerProbe.ServerAddress(typed: "http://cloud.example.com")
        #expect(publicServer?.scheme == "https")
        #expect(publicServer?.port == nil)
        let local = ServerProbe.ServerAddress(typed: "http://192.168.178.162:8080")
        #expect(local?.scheme == "http")
        #expect(local?.port == 8080)
    }

    @Test("An attachment's addresses are secured as they are decoded")
    func attachmentDecoding() throws {
        let json = Data(
            #"{"id":"1","type":"image","url":"http://media.example.com/a.jpg","preview_url":"http://192.168.1.2/p.jpg"}"#
                .utf8)
        let attachment = try AlohaJSON.decoder.decode(MediaAttachment.self, from: json)
        #expect(attachment.url?.scheme == "https")
        #expect(attachment.previewURL?.scheme == "http")
    }
}

// MARK: - Path segments are encoded once

@Suite("Path encoding")
struct PathEncodingTests {

    private func path(_ endpoint: Endpoint) -> String? {
        endpoint.url(base: base)?.path()
    }

    @Test("An announcement reaction names a Unicode emoji, encoded once")
    func announcementReactionEmoji() throws {
        #expect(
            path(Endpoint.announcementsExtra.react("3", emoji: "🌺"))
                == "/api/v1/announcements/3/reactions/%F0%9F%8C%BA")
        #expect(
            path(Endpoint.announcementsExtra.unreact("3", emoji: "👍🏽"))
                == "/api/v1/announcements/3/reactions/%F0%9F%91%8D%F0%9F%8F%BD")
        // A custom emoji is its shortcode, underscore and all.
        #expect(
            path(Endpoint.announcementsExtra.react("3", emoji: "blob_cat"))
                == "/api/v1/announcements/3/reactions/blob_cat")
        // What the server reads back is the emoji itself.
        let url = try #require(Endpoint.announcementsExtra.react("3", emoji: "🌺").url(base: base))
        #expect(url.path(percentEncoded: false).hasSuffix("/reactions/🌺"))
    }

    @Test("An interest's tag is encoded once, whatever its letters")
    func interestTags() {
        #expect(path(Endpoint.interests.remove("café")) == "/api/v1/interests/caf%C3%A9")
        #expect(
            path(Endpoint.interests.pin("über_alles")) == "/api/v1/interests/%C3%BCber_alles/pin")
        #expect(
            path(Endpoint.interests.unpin("two words")) == "/api/v1/interests/two%20words/unpin")
        #expect(path(Endpoint.interests.move("🌺", to: 2)) == "/api/v1/interests/%F0%9F%8C%BA/move")
    }

    @Test("A user name in a path is encoded once")
    func accountInfoUsername() {
        #expect(
            path(Endpoint.socialExtras.accountInfo(username: "jörg m_1"))
                == "/api/v1/account/j%C3%B6rg%20m_1/info")
        #expect(
            path(Endpoint.socialExtras.accountInfo(username: "alice"))
                == "/api/v1/account/alice/info")
    }
}
