// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

@Suite("Watch complications")
struct WatchComplicationTests {
    private let accountID = UUID()

    private func defaults() -> (UserDefaults, String) {
        let name = "aloha.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name) ?? .standard, name)
    }

    private func snapshot(
        updatedAt: Date = Date(timeIntervalSince1970: 2000)
    ) -> WatchComplicationSnapshot {
        WatchComplicationSnapshot(
            accountID: accountID, unreadCount: 4,
            mentions: [
                .init(
                    id: "9", author: "Bob", text: "Hello", statusID: "42",
                    createdAt: Date(timeIntervalSince1970: 1000))
            ],
            updatedAt: updatedAt)
    }

    @Test("A snapshot comes back for its own account only")
    func storageIsPerAccount() {
        let (store, name) = defaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        snapshot().save(to: store)

        #expect(WatchComplicationSnapshot.load(for: accountID, from: store) == snapshot())
        #expect(WatchComplicationSnapshot.load(for: UUID(), from: store) == nil)

        WatchComplicationSnapshot.clear(from: store)
        #expect(WatchComplicationSnapshot.load(for: accountID, from: store) == nil)
    }

    @Test("Stale after the refresh interval, not before")
    func staleness() {
        let now = Date()
        #expect(!snapshot(updatedAt: now.addingTimeInterval(-60)).isStale(at: now))
        #expect(
            snapshot(updatedAt: now.addingTimeInterval(-WatchComplicationSnapshot.refreshInterval))
                .isStale(at: now))
    }

    @Test("The phone's push round-trips, and anything else is ignored")
    func userInfo() throws {
        let info = WatchComplicationSnapshot.unreadUserInfo(accountID: accountID, count: 7)
        let update = try #require(WatchComplicationSnapshot.unreadUpdate(from: info))
        #expect(update.accountID == accountID)
        #expect(update.count == 7)
        #expect(update.conversations == nil)
        #expect(WatchComplicationSnapshot.unreadUpdate(from: ["count": 7]) == nil)

        let applied = snapshot().applying(unreadCount: 7)
        #expect(applied.unreadCount == 7)
        #expect(applied.mentions == snapshot().mentions)
    }

    @Test("The unread conversation count rides along, and a push without one keeps the last")
    func conversations() throws {
        let info = WatchComplicationSnapshot.unreadUserInfo(
            accountID: accountID, count: 7, conversations: 2)
        let update = try #require(WatchComplicationSnapshot.unreadUpdate(from: info))
        #expect(update.conversations == 2)

        let withTwo = snapshot().applying(unreadCount: 7, conversations: 2)
        #expect(withTwo.unreadConversations == 2)
        #expect(withTwo.applying(unreadCount: 8).unreadConversations == 2)
        #expect(withTwo.applying(unreadCount: 8, conversations: 0).unreadConversations == 0)
    }

    @Test("A snapshot an older build wrote decodes, with no conversation count")
    func olderSnapshot() throws {
        let json = """
            {"accountID":"\(accountID.uuidString)","unreadCount":4,"mentions":[],
             "updatedAt":0}
            """
        let decoded = try JSONDecoder().decode(
            WatchComplicationSnapshot.self, from: Data(json.utf8))
        #expect(decoded.unreadCount == 4)
        #expect(decoded.unreadConversations == nil)
    }

    @Test("Links round-trip, and foreign links are not ours")
    func links() throws {
        for link in [WatchComplicationLink.mentions, .status("123"), .messages, .notifications] {
            #expect(WatchComplicationLink(url: link.url) == link)
        }
        #expect(
            WatchComplicationLink.status("123").url.absoluteString
                == "alohasocial://watch/status/123")
        #expect(
            WatchComplicationLink.notifications.url.absoluteString
                == "alohasocial://watch/notifications")
        #expect(
            WatchComplicationLink(url: try #require(URL(string: "alohasocial://compose"))) == nil)
        #expect(
            WatchComplicationLink(url: try #require(URL(string: "alohasocial://watch/status/")))
                == nil)
    }

    @Test("A content warning is shown instead of the post")
    func contentWarning() throws {
        let json = """
            {"id":"1","type":"mention","created_at":"2026-09-20T12:00:00.000Z",
             "account":\(Self.account),
             "status":\(Self.status(spoiler: "Spoilers"))}
            """
        let notification = try AlohaJSON.decoder.decode(
            MastodonNotification.self, from: Data(json.utf8))
        let mention = WatchComplicationRefresher.mention(from: notification) { _ in "Body" }
        #expect(mention.text == "Spoilers")
        #expect(mention.statusID == "5")
        #expect(mention.author == "Bob")
    }

    @Test("The refresher keeps mentions only, and reads the count")
    func refresherAgainstMock() async throws {
        let client = APIClient(
            accountID: accountID,
            apiBase: try #require(URL(string: "https://cloud.example.test/")),
            accessToken: "token",
            transport: MockAPIServer(configuration: .mastodon43))
        let now = Date(timeIntervalSince1970: 5000)
        let fresh = try await WatchComplicationRefresher.fetch(
            client: client, accountID: accountID, now: now
        ) { _ in "text" }

        #expect(fresh.unreadCount == 3)
        #expect(fresh.updatedAt == now)
        // The mock's `conversations/unread_count`.
        #expect(fresh.unreadConversations == 1)
        // The mock's page is favourite, boost, mention: only the last is one.
        #expect(fresh.mentions.count == 1)
        #expect(fresh.mentions.first?.id == "8998")
    }

    @Test("The pairing store saves, loads and forgets")
    func pairingStore() {
        let store = WatchPairingStore(accessGroup: "social.aloha.app", inMemory: true)
        store.remove()
        #expect(store.load() == nil)

        let pairing = WatchPairing(
            accountID: accountID, apiBase: URL(fileURLWithPath: "/"), token: "t", handle: "@a@b")
        store.save(pairing)
        #expect(store.load() == pairing)

        store.remove()
        #expect(store.load() == nil)
    }

    @Test("The app refreshes when the snapshot is missing, old or from the future only")
    func appThrottle() {
        let now = Date(timeIntervalSince1970: 10_000)
        let interval = WatchComplicationSnapshot.appRefreshInterval
        #expect(WatchComplicationSnapshot.appShouldRefresh(nil, at: now))
        #expect(
            !WatchComplicationSnapshot.appShouldRefresh(
                snapshot(updatedAt: now.addingTimeInterval(-30)), at: now))
        #expect(
            WatchComplicationSnapshot.appShouldRefresh(
                snapshot(updatedAt: now.addingTimeInterval(-interval)), at: now))
        #expect(
            WatchComplicationSnapshot.appShouldRefresh(
                snapshot(updatedAt: now.addingTimeInterval(60)), at: now))
        // A pushed count leaves the age alone, so it does not hold a refresh off.
        let pushed = snapshot(updatedAt: now.addingTimeInterval(-interval)).applying(unreadCount: 1)
        #expect(WatchComplicationSnapshot.appShouldRefresh(pushed, at: now))
    }

    @Test("Something unread raises a complication, and nothing unread sinks it")
    func relevance() {
        let now = Date(timeIntervalSince1970: 10_000)
        var quiet = snapshot(updatedAt: now)
        quiet.unreadCount = 0
        quiet.unreadConversations = 0
        for kind in WatchComplicationKind.allCases {
            #expect(quiet.relevance(for: kind, at: now) == .none)
        }

        var busy = quiet
        busy.unreadCount = 4
        busy.unreadConversations = 2
        busy.mentions = [
            .init(
                id: "1", author: "Bob", text: "Hi", statusID: "2",
                createdAt: now.addingTimeInterval(-600))
        ]
        let messages = busy.relevance(for: .directMessages, at: now)
        let unread = busy.relevance(for: .unread, at: now)
        let mentions = busy.relevance(for: .mentions, at: now)
        #expect(messages.score > unread.score)
        #expect(mentions.score > unread.score)
        #expect(mentions.duration == WatchComplicationSnapshot.mentionRelevanceWindow - 600)

        // An hour on, the mention has had its turn.
        let later = now.addingTimeInterval(WatchComplicationSnapshot.mentionRelevanceWindow)
        #expect(busy.relevance(for: .mentions, at: later) == .none)
        // Read on another device: the count is zero, so the mention is old news.
        busy.unreadCount = 0
        #expect(busy.relevance(for: .mentions, at: now) == .none)
        // A count of nil is no claim either way: no rise.
        busy.unreadConversations = nil
        #expect(busy.relevance(for: .directMessages, at: now) == .none)
    }

    @Test("The marker moves to the newest id, and never backwards")
    func markerTarget() {
        #expect(WatchNotificationMarker.target(newestOf: [], current: nil) == nil)
        #expect(WatchNotificationMarker.target(newestOf: ["9", "10", "8"], current: nil) == "10")
        #expect(WatchNotificationMarker.target(newestOf: ["9", "10"], current: "10") == nil)
        #expect(WatchNotificationMarker.target(newestOf: ["9", "10"], current: "11") == nil)
        #expect(WatchNotificationMarker.target(newestOf: ["9", "100"], current: "99") == "100")
    }

    @Test("Marking read writes the marker once, and not behind the server's")
    func markerAgainstMock() async throws {
        let server = MockAPIServer(configuration: .mastodon43)
        let client = APIClient(
            accountID: accountID,
            apiBase: try #require(URL(string: "https://cloud.example.test/")),
            accessToken: "token", transport: server)

        let written = try await WatchNotificationMarker.markRead(["500", "501"], client: client)
        #expect(written == "501")
        #expect(try await WatchNotificationMarker.markRead(["501"], client: client) == nil)
        #expect(try await WatchNotificationMarker.markRead(["499"], client: client) == nil)
        let posts = await server.requestLog.filter {
            $0.method == "POST" && $0.path.hasSuffix("api/v1/markers")
        }
        #expect(posts.count == 1)
        let markers = try await client.decode(MarkerSet.self, from: Endpoint.markers.read)
        #expect(markers.notifications?.lastReadID == "501")
    }

    @Test("Three complications asking at once cost one refresh")
    func refreshGate() async {
        let gate = WatchComplicationRefreshGate()
        let counter = FetchCounter()
        let now = Date(timeIntervalSince1970: 10_000)
        let fresh = snapshot(updatedAt: now)
        let fetch: @Sendable () async -> WatchComplicationSnapshot? = {
            await counter.increment()
            try? await Task.sleep(for: .milliseconds(50))
            return fresh
        }

        async let first = gate.refresh(accountID: accountID, now: now, fetch: fetch)
        async let second = gate.refresh(accountID: accountID, now: now, fetch: fetch)
        async let third = gate.refresh(accountID: accountID, now: now, fetch: fetch)
        let answers = await [first, second, third]
        #expect(answers.allSatisfy { $0 == fresh })
        #expect(await counter.count == 1)

        // Just after: the answer is reused. A minute on, or for another
        // account, it is asked again.
        _ = await gate.refresh(accountID: accountID, now: now.addingTimeInterval(30), fetch: fetch)
        #expect(await counter.count == 1)
        _ = await gate.refresh(
            accountID: accountID,
            now: now.addingTimeInterval(WatchComplicationRefreshGate.reuseInterval), fetch: fetch)
        #expect(await counter.count == 2)
        _ = await gate.refresh(accountID: UUID(), now: now, fetch: fetch)
        #expect(await counter.count == 3)
    }

    @Test("A failed refresh is reused too, so three timelines do not retry at once")
    func refreshGateFailure() async {
        let gate = WatchComplicationRefreshGate()
        let counter = FetchCounter()
        let now = Date(timeIntervalSince1970: 10_000)
        let failing: @Sendable () async -> WatchComplicationSnapshot? = {
            await counter.increment()
            return nil
        }
        #expect(await gate.refresh(accountID: accountID, now: now, fetch: failing) == nil)
        #expect(
            await gate.refresh(
                accountID: accountID, now: now.addingTimeInterval(5), fetch: failing) == nil)
        #expect(await counter.count == 1)
    }

    @Test("Quick replies are trimmed, unique, short and at most eight")
    func quickRepliesSanitized() {
        let long = String(repeating: "a", count: WatchQuickReplies.maxLength + 20)
        let phrases = ["  Thanks ", "", "thanks", "Yes", long] + (1...10).map { "Phrase \($0)" }
        let clean = WatchQuickReplies.sanitized(phrases)
        #expect(clean.count == WatchQuickReplies.limit)
        #expect(clean[0] == "Thanks")
        #expect(clean[1] == "Yes")
        #expect(clean[2].count == WatchQuickReplies.maxLength)
        #expect(!WatchQuickReplies.builtIn.isEmpty)
        #expect(WatchQuickReplies.builtIn.count <= WatchQuickReplies.limit)
    }

    @Test("Quick replies: absent means built in, empty means none, both ways")
    func quickRepliesStorageAndContext() {
        let (store, name) = defaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        #expect(WatchQuickReplies.stored(in: store) == nil)
        #expect(WatchQuickReplies.current(in: store) == WatchQuickReplies.builtIn)
        WatchQuickReplies.store(["On my way", "On my way"], in: store)
        #expect(WatchQuickReplies.current(in: store) == ["On my way"])
        WatchQuickReplies.store([], in: store)
        #expect(WatchQuickReplies.current(in: store) == [])
        WatchQuickReplies.store(nil, in: store)
        #expect(WatchQuickReplies.stored(in: store) == nil)

        let base: [String: Any] = [WatchPairing.contextKey: Data()]
        #expect(WatchQuickReplies.phrases(in: WatchQuickReplies.adding(nil, to: base)) == nil)
        let context = WatchQuickReplies.adding(["Hi", " "], to: base)
        #expect(WatchQuickReplies.phrases(in: context) == ["Hi"])
        #expect(context[WatchPairing.contextKey] != nil)
        #expect(WatchQuickReplies.phrases(in: WatchQuickReplies.adding([], to: base)) == [])
    }

    private static let account = """
        {"id":"2","username":"bob","acct":"bob","display_name":"Bob","url":"https://x/@bob",
         "avatar":"","header":"","note":"","followers_count":0,"following_count":0,
         "statuses_count":0,"created_at":"2026-01-01T00:00:00.000Z"}
        """

    private static func status(spoiler: String) -> String {
        """
        {"id":"5","created_at":"2026-09-20T12:00:00.000Z","content":"<p>Body</p>",
         "spoiler_text":"\(spoiler)","visibility":"public","sensitive":true,
         "account":\(account),"media_attachments":[],"mentions":[],"tags":[],"emojis":[]}
        """
    }
}

private actor FetchCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
