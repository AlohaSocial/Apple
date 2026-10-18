// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

private func form(_ endpoint: Endpoint) -> [URLQueryItem] {
    guard case .form(let items) = endpoint.body else { return [] }
    return items
}

private func formValue(_ endpoint: Endpoint, _ name: String) -> String? {
    form(endpoint).first { $0.name == name }?.value
}

private func jsonObject(_ endpoint: Endpoint) throws -> [String: Any] {
    guard case .json(let data) = endpoint.body else {
        Issue.record("not a JSON body")
        return [:]
    }
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private let base = URL(string: "https://cloud.example.test/")!

@Suite("Posting with Aloha Social's policies")
struct PostPolicyTests {
    @Test("The quote policy goes out under the name the server reads")
    func quoteApprovalPolicy() {
        // `Status::import` reads `quote_approval_policy`; `quote_policy` was
        // read by nothing.
        let post = StatusPost(text: "Hi", quotePolicy: "followers", replyPolicy: .mentioned)
        let endpoint = Endpoint.composing.post(post)
        #expect(formValue(endpoint, "quote_approval_policy") == "followers")
        #expect(formValue(endpoint, "quote_policy") == nil)
        #expect(formValue(endpoint, "reply_policy") == "mentioned")
    }

    @Test("A post without a reply policy sends none")
    func noReplyPolicy() {
        let endpoint = Endpoint.composing.post(StatusPost(text: "Hi"))
        #expect(formValue(endpoint, "reply_policy") == nil)
    }

    @Test("Changing who may reply sends only reply_policy")
    func setReplyPolicy() {
        let endpoint = Endpoint.replyControls.setReplyPolicy("7", .nobody)
        #expect(endpoint.method == .put)
        #expect(endpoint.path == "api/v1/statuses/7/interaction_policy")
        #expect(form(endpoint).map(\.name) == ["reply_policy"])
        #expect(formValue(endpoint, "reply_policy") == "nobody")
    }

    @Test("Hiding names the reply")
    func hideReply() {
        #expect(Endpoint.replyControls.hide("9").path == "api/v1/statuses/9/hide_reply")
        #expect(Endpoint.replyControls.unhide("9").path == "api/v1/statuses/9/unhide_reply")
        #expect(Endpoint.replyControls.hide("9").method == .post)
    }
}

@Suite("Reader settings endpoints")
struct ReaderSettingsEndpointTests {
    @Test("The two hide switches PATCH a JSON boolean")
    func hideSwitches() throws {
        let ai = Endpoint.readerSettings.setAIContent(hide: true)
        #expect(ai.method == .patch)
        #expect(ai.path == "api/v1/social/ai_content")
        #expect(try jsonObject(ai)["hide"] as? Bool == true)

        let counts = Endpoint.readerSettings.setCounts(hide: false)
        #expect(counts.path == "api/v1/social/counts")
        #expect(try jsonObject(counts)["hide"] as? Bool == false)
    }

    @Test("Who may message sends `from`")
    func directMessages() throws {
        let endpoint = Endpoint.readerSettings.setDirectMessages(from: .following)
        #expect(endpoint.path == "api/v1/social/direct_messages")
        #expect(try jsonObject(endpoint)["from"] as? String == "following")
    }

    @Test("Notification delivery goes back whole, in the server's shape")
    func delivery() throws {
        let settings = NotificationDeliverySettings(
            mode: .digest, times: ["08:00", "20:00"], quietFrom: "22:00", quietTo: "07:00")
        let object = try jsonObject(Endpoint.readerSettings.setNotificationDelivery(settings))
        #expect(object["mode"] as? String == "digest")
        #expect(object["times"] as? [String] == ["08:00", "20:00"])
        #expect((object["quiet"] as? [String: String])?["to"] == "07:00")
        #expect((object["passthrough"] as? [String: Bool])?["direct"] == true)
    }

    @Test("Reading signals are a JSON list of objects, learnable ones only")
    func signals() throws {
        let events = [
            InterestSignal(statusID: "12", kind: .dwell, milliseconds: 2000, context: .home),
            InterestSignal(statusID: "https://elsewhere/1", kind: .open, context: .detail),
        ]
        let endpoint = Endpoint.interests.signals(events)
        #expect(endpoint.method == .post)
        let sent = try #require(try jsonObject(endpoint)["events"] as? [[String: Any]])
        #expect(sent.count == 1)
        #expect(sent[0]["status_id"] as? String == "12")
        #expect(sent[0]["kind"] as? String == "dwell")
    }

    @Test("No more than the server's hundred go in one request")
    func signalCap() throws {
        let events = (0..<150).map {
            InterestSignal(statusID: String($0 + 1), kind: .skip, context: .interests)
        }
        let sent = try #require(
            try jsonObject(Endpoint.interests.signals(events))["events"] as? [[String: Any]])
        #expect(sent.count == 100)
    }
}

@Suite("Bluesky and session-authenticated routes")
struct BlueskyEndpointTests {
    @Test("Every Bluesky route uses the Nextcloud session")
    func authentication() {
        let routes: [Endpoint] = [
            .bluesky.feeds, .bluesky.suggestedFeeds, .bluesky.addFeed("at://x"),
            .bluesky.removeFeed(uri: "at://x"), .bluesky.identity, .bluesky.setActive(false),
            .bluesky.setPublishBlocks(true), .moderationLists.all,
            .moderationLists.subscribe(url: "https://bsky.app/x", kind: .block),
            .moderationLists.unsubscribe(uri: "at://x"),
            .timelines.timeline(.bluesky(feedURI: "at://x")),
        ]
        for route in routes {
            #expect(route.authentication == .nextcloudSession, "\(route.path)")
        }
    }

    @Test("A Bluesky feed timeline names the feed and pages by max_id")
    func timeline() throws {
        let endpoint = Endpoint.timelines.timeline(
            .bluesky(feedURI: "at://did:plc:a/app.bsky.feed.generator/cats"),
            anchor: .olderThan("99"))
        #expect(endpoint.path == "api/v1/timelines/bluesky")
        let url = try #require(endpoint.url(base: base))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(
            items.first { $0.name == "feed" }?.value
                == "at://did:plc:a/app.bsky.feed.generator/cats")
        #expect(items.first { $0.name == "max_id" }?.value == "99")
        #expect(items.first { $0.name == "local" } == nil)
    }

    @Test("Removing takes its uri in the query, where Nextcloud reads it")
    func removeInQuery() {
        let endpoint = Endpoint.bluesky.removeFeed(uri: "at://x")
        #expect(endpoint.method == .delete)
        #expect(endpoint.body == nil)
        #expect(endpoint.query.first { $0.name == "uri" }?.value == "at://x")
    }

    @Test("Presence and publishing are sent as 1 or 0")
    func flags() {
        #expect(formValue(.bluesky.setActive(false), "active") == "0")
        #expect(formValue(.bluesky.setPublishBlocks(true), "publish") == "1")
    }
}

@Suite("Shorts and links")
struct ShortsAndLinksEndpointTests {
    @Test("Shorts ask for only_short beside only_video")
    func onlyShort() throws {
        let endpoint = Endpoint.timelines.timeline(
            .home, filters: TimelineFilters(onlyVideo: true, onlyShort: true))
        let names = endpoint.query.map(\.name)
        #expect(names.contains("only_video"))
        #expect(names.contains("only_short"))
        #expect(
            !Endpoint.timelines.timeline(.home, filters: TimelineFilters(onlyVideo: true))
                .query.map(\.name).contains("only_short"))
    }

    @Test("The link timeline carries the address")
    func linkTimeline() {
        let link = URL(string: "https://news.example/story?id=1")!
        let endpoint = Endpoint.socialExtras.linkTimeline(link)
        #expect(endpoint.path == "api/v1/timelines/link")
        #expect(endpoint.query.first { $0.name == "url" }?.value == link.absoluteString)
    }

    @Test("Bulk request decisions send id[]")
    func bulkRequests() {
        let endpoint = Endpoint.notificationInbox.acceptAll(["1", "2"])
        #expect(endpoint.path == "api/v1/notifications/requests/accept")
        #expect(form(endpoint).filter { $0.name == "id[]" }.compactMap(\.value) == ["1", "2"])
        #expect(
            Endpoint.notificationInbox.removeAllowed("5").path
                == "api/v1/social/notifications/allowed/5")
    }
}

@Suite("Account not set up")
struct AccountNotSetUpTests {
    @Test("The server's coded 403 becomes its own error, with the address to go to")
    func coded403() throws {
        let body = Data(
            #"{"error":"Your account is not set up yet.","code":"account-not-set-up","setup_url":"https://cloud.example.test/apps/social/"}"#
                .utf8)
        let error = try #require(APIError.from(status: 403, data: body, headers: [:]))
        #expect(error.isAccountNotSetUp)
        #expect(error.accountSetupURL == URL(string: "https://cloud.example.test/apps/social/"))
        #expect(error.errorDescription == "Your account is not set up yet.")
        #expect(!error.requiresReauthentication)
    }

    @Test("Any other 403 is still a refusal")
    func plain403() throws {
        let error = try #require(
            APIError.from(status: 403, data: Data(#"{"error":"No."}"#.utf8), headers: [:]))
        #expect(!error.isAccountNotSetUp)
        #expect(error.accountSetupURL == nil)
    }

    @Test("A setup address that is not a web page is dropped")
    func unsafeSetupURL() throws {
        let body = Data(
            #"{"error":"x","code":"account-not-set-up","setup_url":"file:///etc"}"#.utf8)
        let error = try #require(APIError.from(status: 403, data: body, headers: [:]))
        #expect(error.isAccountNotSetUp)
        #expect(error.accountSetupURL == nil)
    }
}

@Suite("Against the mock server")
struct SocialMockTests {
    private func client(_ configuration: MockAPIServer.Configuration) -> APIClient {
        APIClient(
            accountID: UUID(), apiBase: base, accessToken: "token",
            transport: MockAPIServer(configuration: configuration))
    }

    @Test("Bluesky is available only with a Nextcloud session, on a server that has it")
    func blueskyProbe() async {
        let nextcloud = client(.nextcloudSocialWithRewrite)
        #expect(await BlueskyAvailability.probe(nextcloud) == .needsNextcloudConnection)
        await nextcloud.updateNextcloudAuthorization("Basic eDp5")
        #expect(await BlueskyAvailability.probe(nextcloud) == .available)

        let mastodon = client(.mastodon43)
        await mastodon.updateNextcloudAuthorization("Basic eDp5")
        #expect(await BlueskyAvailability.probe(mastodon) == .off)
    }

    @Test("A switch round-trips through the server")
    func countsRoundTrip() async throws {
        let api = client(.nextcloudSocialWithRewrite)
        let changed = try await api.decode(
            HideSetting.self, from: .readerSettings.setAIContent(hide: true))
        #expect(changed.hide)
        let read = try await api.decode(HideSetting.self, from: .readerSettings.aiContent)
        #expect(read.hide)
        _ = try await api.decode(HideSetting.self, from: .readerSettings.setAIContent(hide: false))
    }

    @Test("Notification delivery reads in the shape it is written")
    func delivery() async throws {
        let api = client(.nextcloudSocialWithRewrite)
        let read = try await api.decode(
            NotificationDeliverySettings.self, from: .readerSettings.notificationDelivery)
        #expect(read.mode == .instant)
        var digest = read
        digest.mode = .digest
        let written = try await api.decode(
            NotificationDeliverySettings.self, from: .readerSettings.setNotificationDelivery(digest)
        )
        #expect(written.mode == .digest)
        digest.mode = .instant
        _ = try await api.send(.readerSettings.setNotificationDelivery(digest))
    }

    @Test("A local account's info carries its Bluesky handle")
    func accountInfo() async throws {
        let api = client(.nextcloudSocialWithRewrite)
        let account = try await api.decode(
            Account.self, from: .socialExtras.accountInfo(username: "alice"))
        #expect(account.bluesky?.handle.hasPrefix("alice.") == true)
    }

    @Test("A stock Mastodon has none of these routes")
    func mastodonRefuses() async {
        let api = client(.mastodon43)
        await #expect(throws: APIError.self) {
            _ = try await api.decode(HideSetting.self, from: .readerSettings.counts)
        }
    }
}

@Suite("For you")
struct ForYouEndpointTests {
    private func value(_ name: String, in endpoint: Endpoint) -> String? {
        endpoint.query.first { $0.name == name }?.value
    }

    @Test("For you is the interests timeline, narrowed by the server's own parameters")
    func narrowing() {
        let home = Endpoint.timelines.timeline(.interests)
        #expect(home.path == "api/v1/timelines/interests")
        #expect(value("media", in: home) == nil)

        let photos = Endpoint.timelines.timeline(
            .interests, filters: TimelineFilters(onlyMedia: true))
        #expect(value("media", in: photos) == "photos")
        #expect(value("only_media", in: photos) == nil)

        let videos = Endpoint.timelines.timeline(
            .interests, filters: TimelineFilters(onlyVideo: true))
        #expect(value("media", in: videos) == "videos")

        let shorts = Endpoint.timelines.timeline(
            .interests, filters: TimelineFilters(onlyVideo: true, onlyShort: true))
        #expect(value("only_short", in: shorts) == "true")
        #expect(value("media", in: shorts) == nil)
    }
}
