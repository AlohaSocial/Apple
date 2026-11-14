// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

/// Where the live contract tests point, from the environment. Both values
/// or neither: without them the suite is skipped, which is what every
/// ordinary run — local or CI — does.
///
/// - `ALOHA_LIVE_SERVER_URL`: the server, as a person would type it at
///   sign-in (`https://cloud.example.com`). The API base is discovered the
///   way the app discovers it, so a Nextcloud without the rewrite rules works
///   as well as one with them.
/// - `ALOHA_LIVE_TOKEN`: an OAuth access token for a test account on it,
///   with `read` and `write:statuses` at least. The only write the suite makes
///   is the notifications marker, posted back as it already was.
private enum LiveServer {
    static var url: URL? {
        guard let raw = value("ALOHA_LIVE_SERVER_URL") else { return nil }
        return URL(string: raw)
    }

    static var token: String? { value("ALOHA_LIVE_TOKEN") }

    static var isConfigured: Bool { url != nil && token != nil }

    private static func value(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment[name]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

/// The routes the app cannot work without, asked of a real server and
/// decoded with the app's own types (docs/12 §2).
///
/// The mock server answers in the shapes the fixtures were captured in; it
/// cannot say when a server changes its shapes. These tests can. They are
/// read-only apart from one marker write that changes nothing, so they are
/// safe against a real account — but use a test account all the same.
@Suite(
    "Live server contract",
    .enabled(
        if: LiveServer.isConfigured,
        "Set ALOHA_LIVE_SERVER_URL and ALOHA_LIVE_TOKEN to run against a real server"),
    .serialized)
struct LiveServerContractTests {
    private let transport = URLSessionTransport()

    /// The API base as the app would find it, and a client for it.
    private func connect() async throws -> (client: APIClient, instance: InstanceDescription) {
        let url = try #require(LiveServer.url)
        let resolved = try #require(
            await ServerProbe(transport: transport).resolveInstance(base: url),
            "No Mastodon API answered at the configured server")
        let client = APIClient(
            accountID: UUID(), apiBase: resolved.base, accessToken: LiveServer.token,
            transport: transport)
        return (client, resolved.instance)
    }

    @Test("The instance describes itself")
    func instance() async throws {
        let (_, instance) = try await connect()
        #expect(!instance.domain.isEmpty)
        #expect(!instance.version.isEmpty)
    }

    @Test("verify_credentials decodes as the signed-in account")
    func verifyCredentials() async throws {
        let (client, _) = try await connect()
        let account = try await client.decode(
            Account.self, from: Endpoint.session.verifyCredentials)
        #expect(!account.id.isEmpty)
        #expect(!account.acct.isEmpty)
    }

    @Test("Every post on the home timeline decodes")
    func homeTimeline() async throws {
        let (client, _) = try await connect()
        let page = try await client.page(
            LossyArray<Status>.self, from: Endpoint.timelines.timeline(.home, limit: 20),
            limit: 20)
        // Lossy decoding drops what it cannot read; a contract break shows
        // as rows the server sent and the app lost.
        #expect(page.value.elements.count == page.rawCount)
    }

    @Test("Every notification decodes, grouped where the server groups")
    func notifications() async throws {
        let (client, _) = try await connect()
        do {
            let grouped = try await client.page(
                GroupedNotificationsResults.self,
                from: Endpoint.notifications.grouped(limit: 20), limit: 20)
            #expect(grouped.value.notificationGroups.count == grouped.rawCount)
            return
        } catch APIError.notFound {
            // Before Mastodon 4.3 there is only the flat list.
        }
        let flat = try await client.page(
            LossyArray<MastodonNotification>.self,
            from: Endpoint.notifications.flat(limit: 20), limit: 20)
        #expect(flat.value.elements.count == flat.rawCount)
    }

    /// The badge is this route where it exists. Where it does not, the app
    /// counts from the notifications marker instead — which the marker test
    /// below covers — so a 404 is a finding to know about, not a failure.
    @Test("unread_count decodes where it is served")
    func unreadCount() async throws {
        let (client, _) = try await connect()
        var answered = false
        for grouped in [true, false] {
            do {
                let count = try await client.decode(
                    UnreadCount.self, from: Endpoint.notifications.unreadCount(grouped: grouped))
                #expect(count.count >= 0)
                answered = true
            } catch APIError.notFound {
                continue
            }
        }
        if !answered {
            print("notifications/unread_count is not served here; the app counts from markers")
        }
    }

    @Test("Markers read, and write back unchanged")
    func markers() async throws {
        let (client, _) = try await connect()
        let markers = try await client.decode(MarkerSet.self, from: Endpoint.markers.read)
        // Posting the marker it already has is the one write that changes
        // nothing: a marker never moves backwards, and this does not move it
        // at all. An account with no marker yet is left without one.
        guard let current = markers.notifications?.lastReadID else { return }
        let written = try await client.decode(
            MarkerSet.self, from: Endpoint.markers.write(home: nil, notifications: current))
        #expect(written.notifications?.lastReadID == current)
    }

    /// The count of unread direct conversations. A server without the route
    /// gets the loaded page standing in for it (`ConversationsView`).
    @Test("conversations/unread_count decodes where it is served")
    func conversationsUnreadCount() async throws {
        let (client, _) = try await connect()
        do {
            let count = try await client.decode(
                UnreadCount.self, from: Endpoint.timelines.conversationsUnreadCount)
            #expect(count.count >= 0)
        } catch APIError.notFound {
            print("conversations/unread_count is not served here")
        }
    }
}
