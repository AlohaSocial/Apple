// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import AlohaUI

private let base = URL(string: "https://cloud.example.test/")!

/// An environment whose every request is answered by `transport`, with the
/// network stated rather than read from the machine running the tests.
@MainActor
private func makeEnvironment(_ transport: any HTTPTransport) -> AppEnvironment {
    let environment = AppEnvironment(
        container: StoreContainer.make(inMemory: true), transport: transport,
        credentials: CredentialStore(inMemory: true))
    environment.sync.network.simulate(isSatisfied: true)
    environment.sync.attach(to: environment)
    return environment
}

@MainActor
private func signIn(
    _ environment: AppEnvironment, token: String = "token", accountID: String = "1"
) async throws -> AccountSession {
    try await environment.addAccount(
        instanceHost: "cloud.example.test", apiBase: base,
        account: Account(id: accountID, username: "user\(accountID)", acct: "user\(accountID)"),
        capabilities: .minimal(apiBase: base), token: token)
}

/// Waits, a little at a time, for something the engine does on its own.
@MainActor
private func eventually(
    within timeout: Duration = .seconds(5), _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

@Suite("Sync engine")
@MainActor
struct SyncEngineTests {
    // MARK: - The badge

    @Test("A poll publishes the unread count, and forgetting the account takes it back")
    func badgeCountPublishAndForget() async throws {
        let environment = makeEnvironment(MockAPIServer(configuration: .mastodon43))
        let session = try await signIn(environment)

        #expect(await environment.sync.poll(session) == 3)
        #expect(environment.sync.unreadCounts[session.id] == 3)
        #expect(environment.sync.lastPoll[session.id] != nil)

        await environment.sync.forget(session.id)
        #expect(environment.sync.unreadCounts[session.id] == nil)
        #expect(environment.sync.lastPoll[session.id] == nil)
    }

    /// Mastodon before 4.3, GoToSocial, Akkoma and Pleroma have no
    /// `unread_count`. A poll used to fail on it and only ever back off, so
    /// notifications were never fetched there at all.
    @Test("Without unread_count the badge is counted from the notifications marker")
    func unreadCountFallback() async throws {
        let server = MockAPIServer(configuration: .withoutUnreadCount)
        let environment = makeEnvironment(server)
        let session = try await signIn(environment)

        // No marker yet: every notification on the page is unread.
        #expect(await environment.sync.poll(session) == 3)
        #expect(environment.sync.unreadCountMissing.contains(session.id))

        // Read up to the second newest, elsewhere: the server's marker counts.
        try await session.client.send(
            Endpoint.markers.write(home: nil, notifications: "8999"))
        #expect(await environment.sync.poll(session) == 1)

        // The missing route is remembered rather than asked about each poll.
        let asked = await server.loggedPaths.filter { $0.hasSuffix("unread_count") }
        #expect(asked.count == 1)
        // The page that was counted is the one stored to announce from:
        // nothing was fetched twice.
        let id = session.id
        let stored = try ModelContext(environment.container).fetchCount(
            FetchDescriptor<NotificationRecord>(predicate: #Predicate { $0.accountID == id }))
        #expect(stored == 3)
        let fetched = await server.loggedPaths.filter { $0.hasSuffix("api/v1/notifications") }
        #expect(fetched.count == 2)
    }

    @Test("A failing poll goes out without waiting for connectivity")
    func pollsFailFast() async throws {
        let transport = RecordingTransport()
        let environment = makeEnvironment(transport)
        let session = try await signIn(environment)

        _ = await environment.sync.poll(session)
        let failingFast = await transport.failingFastPaths
        #expect(failingFast.contains { $0.hasSuffix("notifications/unread_count") })
    }

    // MARK: - The timeline

    @Test("A poll with the home timeline recently on screen asks it to refresh")
    func pollRequestsTimelineRefresh() async throws {
        let environment = makeEnvironment(MockAPIServer(configuration: .mastodon43))
        let session = try await signIn(environment)
        let sync = environment.sync

        // Not on screen: nothing to refresh.
        _ = await sync.poll(session)
        #expect(sync.timelineRefreshRequests[session.id, default: 0] == 0)

        sync.noteTimelineVisible(for: session.id)
        _ = await sync.poll(session)
        #expect(sync.timelineRefreshRequests[session.id] == 1)

        // A notifications-only poll — background refresh, Wi-Fi-only on
        // cellular — leaves the timeline alone.
        _ = await sync.poll(session, scope: .notificationsOnly)
        #expect(sync.timelineRefreshRequests[session.id] == 1)
    }

    @Test("Posts from the socket ask the timeline to refresh, once per burst")
    func streamedPostsRequestOneRefresh() async throws {
        let environment = makeEnvironment(MockAPIServer(configuration: .mastodon43))
        let session = try await signIn(environment)
        let sync = environment.sync
        sync.streamRefreshDelay = .milliseconds(50)

        let json = try JSONSerialization.data(withJSONObject: Fixtures.status(index: 0))
        let status = try AlohaJSON.decoder.decode(Status.self, from: json)
        for _ in 0..<3 { await sync.handle(.update(status), session: session) }

        #expect(await eventually { sync.timelineRefreshRequests[session.id] == 1 })
        try await Task.sleep(for: .milliseconds(150))
        #expect(sync.timelineRefreshRequests[session.id] == 1)
    }

    // MARK: - Starting and stopping

    @Test("An account added while sync runs is polled at once")
    func addingAnAccountStartsPolling() async throws {
        let environment = makeEnvironment(MockAPIServer(configuration: .mastodon43))
        environment.sync.start()

        let session = try await signIn(environment)

        #expect(environment.sync.isPolling(session))
        // Promptly, not after a first interval's sleep.
        #expect(await eventually { environment.sync.unreadCounts[session.id] == 3 })
    }

    @Test("Signing in again replaces the old session's poll loop")
    func signingInAgainRestartsPolling() async throws {
        let environment = makeEnvironment(MockAPIServer(configuration: .mastodon43))
        environment.sync.start()
        let first = try await signIn(environment, token: "old")
        #expect(environment.sync.isPolling(first))
        await first.markNeedsReauthentication()

        let renewed = try await signIn(environment, token: "new")

        #expect(renewed !== first)
        #expect(environment.sync.isPolling(renewed))
        #expect(!environment.sync.isPolling(first))
    }

    @Test("Starting again leaves a running loop alone")
    func repeatedStartsDoNotStampede() async throws {
        let server = MockAPIServer(configuration: .mastodon43)
        let environment = makeEnvironment(server)
        let session = try await signIn(environment)
        environment.sync.start()
        #expect(await eventually { environment.sync.unreadCounts[session.id] == 3 })

        for _ in 0..<5 { environment.sync.start() }
        try await Task.sleep(for: .milliseconds(200))

        let asked = await server.loggedPaths.filter { $0.hasSuffix("unread_count") }
        #expect(asked.count == 1)
    }

    @Test("Inactive keeps sync running; only every window in the background stops it")
    func inactiveVersusBackground() async throws {
        let environment = makeEnvironment(MockAPIServer(configuration: .mastodon43))
        let session = try await signIn(environment)
        let sync = environment.sync
        let first = UUID()
        let second = UUID()

        sync.scene(first, didEnter: .active)
        #expect(sync.isPolling(session))

        // Control Center, Face ID, another window focused.
        sync.scene(first, didEnter: .inactive)
        #expect(sync.isPolling(session))

        sync.scene(second, didEnter: .active)
        sync.scene(first, didEnter: .background)
        #expect(sync.isPolling(session))

        sync.scene(second, didEnter: .background)
        #expect(!sync.isRunning)
        #expect(!sync.isPolling(session))

        sync.scene(first, didEnter: .active)
        #expect(sync.isPolling(session))

        // A window closed without passing through the background.
        sync.sceneDidDisappear(first)
        #expect(!sync.isPolling(session))
    }

    @Test("Manual frequency waits without a timer, and switching back polls again")
    func manualFrequencyRestarts() async throws {
        let environment = makeEnvironment(MockAPIServer(configuration: .mastodon43))
        let session = try await signIn(environment)
        await session.updateSettings { $0.pollFrequency = .manual }

        environment.sync.start()
        try await Task.sleep(for: .milliseconds(200))
        #expect(environment.sync.unreadCounts[session.id] == nil)
        // The loop is waiting for the setting, not gone.
        #expect(environment.sync.isPolling(session))

        await session.updateSettings { $0.pollFrequency = .normal }
        #expect(await eventually { environment.sync.unreadCounts[session.id] == 3 })
    }

    @Test("Offline, polling pauses; it resumes on the path update")
    func offlinePausesPolling() async throws {
        let environment = makeEnvironment(MockAPIServer(configuration: .mastodon43))
        let session = try await signIn(environment)
        environment.sync.network.simulate(isSatisfied: false)

        environment.sync.start()
        try await Task.sleep(for: .milliseconds(200))
        #expect(environment.sync.unreadCounts[session.id] == nil)

        environment.sync.network.simulate(isSatisfied: true)
        #expect(await eventually { environment.sync.unreadCounts[session.id] == 3 })
    }

    @Test("Wi-Fi-only sync polls notifications only on cellular")
    func wifiOnlySyncNarrowsScope() async throws {
        let environment = makeEnvironment(MockAPIServer(configuration: .mastodon43))
        let session = try await signIn(environment)
        let sync = environment.sync

        sync.network.simulate(isSatisfied: true, isCellular: true)
        #expect(sync.currentScheduler(for: session).scope == .full)

        await session.updateSettings { $0.syncOverWiFiOnly = true }
        #expect(sync.currentScheduler(for: session).scope == .notificationsOnly)

        sync.network.simulate(isSatisfied: true, isCellular: false)
        #expect(sync.currentScheduler(for: session).scope == .full)
    }

    // MARK: - Etiquette

    @Test("A 429 halves the polling frequency for that host")
    func rateLimitSlowsPolling() async throws {
        let environment = makeEnvironment(MockAPIServer(configuration: .rateLimited))
        let session = try await signIn(environment)
        let sync = environment.sync
        let normal = try #require(sync.currentScheduler(for: session).interval)
        #expect(!sync.isSlowedDown(session))

        _ = await sync.poll(session)

        #expect(sync.isSlowedDown(session))
        // One failure's backoff is at most two seconds, well inside this.
        #expect(sync.pollInterval(for: session, streamIsOpen: false) == normal * 2)
    }

    @Test("Accounts on one host share one rate limit")
    func rateLimiterIsSharedPerHost() async throws {
        let transport = ThrottlingTransport()
        let environment = makeEnvironment(transport)
        let alice = try await signIn(environment, token: "alice", accountID: "1")
        let bob = try await signIn(environment, token: "bob", accountID: "2")
        // Let the sign-in refreshes finish before the server starts refusing.
        try await Task.sleep(for: .milliseconds(300))

        await transport.refuse(token: "alice")
        _ = await environment.sync.poll(alice)
        let before = await transport.requestCount

        // Bob was never refused, but his requests go to the same host: they
        // wait out the same `Retry-After` and never reach the server.
        _ = await environment.sync.poll(bob)
        #expect(await transport.requestCount == before)
        #expect(environment.sync.unreadCounts[bob.id] == nil)
    }
}

// MARK: - Transports

/// The mock server, noting which requests were sent failing fast.
private actor RecordingTransport: HTTPTransport {
    let server = MockAPIServer(configuration: .mastodon43)
    private(set) var failingFastPaths: [String] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await server.send(request)
    }

    func sendFailingFast(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        failingFastPaths.append(request.url?.path() ?? "")
        return try await server.send(request)
    }
}

/// The mock server, answering 429 with a long `Retry-After` to one token.
private actor ThrottlingTransport: HTTPTransport {
    let server = MockAPIServer(configuration: .mastodon43)
    private(set) var requestCount = 0
    private var refusedToken: String?

    func refuse(token: String) { refusedToken = token }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        if let refusedToken,
            request.value(forHTTPHeaderField: "Authorization") == "Bearer \(refusedToken)",
            let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: 429, httpVersion: "HTTP/1.1",
                headerFields: ["Retry-After": "120"])
        {
            return (Data(#"{"error":"Too many requests"}"#.utf8), response)
        }
        return try await server.send(request)
    }
}
