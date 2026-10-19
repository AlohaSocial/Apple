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
        #expect(WatchComplicationSnapshot.unreadUpdate(from: ["count": 7]) == nil)

        let applied = snapshot().applying(unreadCount: 7)
        #expect(applied.unreadCount == 7)
        #expect(applied.mentions == snapshot().mentions)
    }

    @Test("Links round-trip, and foreign links are not ours")
    func links() throws {
        for link in [WatchComplicationLink.mentions, .status("123")] {
            #expect(WatchComplicationLink(url: link.url) == link)
        }
        #expect(
            WatchComplicationLink.status("123").url.absoluteString
                == "alohasocial://watch/status/123")
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
