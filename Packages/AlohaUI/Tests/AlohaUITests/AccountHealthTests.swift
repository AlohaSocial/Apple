// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import SwiftData
import Testing

@testable import AlohaUI

/// Answers `verify_credentials` as told, and everything else from the mock.
private actor ScriptedTransport: HTTPTransport {
    let server = MockAPIServer(configuration: .mastodon43, statusCount: 1)
    var verifyFailure: APIError?
    private(set) var verifyCount = 0
    private(set) var cacheCleared = false

    func failVerification(with error: APIError?) { verifyFailure = error }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path().hasSuffix("accounts/verify_credentials") == true {
            verifyCount += 1
            // Long enough for concurrent checks to overlap.
            try? await Task.sleep(for: .milliseconds(50))
            if let verifyFailure { throw verifyFailure }
        }
        return try await server.send(request)
    }

    nonisolated func removeCachedResponses() {
        Task { await markCleared() }
    }

    private func markCleared() { cacheCleared = true }
}

@MainActor
private func makeEnvironment() -> (AppEnvironment, ScriptedTransport) {
    let transport = ScriptedTransport()
    let environment = AppEnvironment(
        container: StoreContainer.make(inMemory: true), transport: transport,
        credentials: CredentialStore(inMemory: true))
    return (environment, transport)
}

private let base = URL(string: "https://cloud.example.test/")!

@MainActor
private func signIn(
    _ environment: AppEnvironment, token: String, accountID: String = "1"
) async throws -> AccountSession {
    try await environment.addAccount(
        instanceHost: "cloud.example.test", apiBase: base,
        account: Account(id: accountID, username: "alice", acct: "alice"),
        capabilities: .minimal(apiBase: base), token: token)
}

@Suite("Signing in and out")
@MainActor
struct AccountLifecycleTests {
    @Test("Signing in again to the same account renews it rather than adding a second")
    func reauthenticationReplacesToken() async throws {
        let (environment, _) = makeEnvironment()
        let first = try await signIn(environment, token: "old")
        await first.markNeedsReauthentication()
        _ = try await first.supportStore.saveDraft(
            DraftSnapshot(accountID: first.id, text: "still mine", queuedForSend: true))

        let again = try await signIn(environment, token: "new")

        #expect(environment.sessions.count == 1)
        #expect(again.id == first.id)
        #expect(try environment.credentials.token(for: first.id) == "new")
        #expect(!again.needsReauthentication)
        // The drafts belong to the same account still.
        #expect(try await again.supportStore.queuedDrafts(accountID: again.id).count == 1)
    }

    @Test("Another person on the same server is a second account")
    func differentAccountIsAdded() async throws {
        let (environment, _) = makeEnvironment()
        _ = try await signIn(environment, token: "a", accountID: "1")
        _ = try await signIn(environment, token: "b", accountID: "2")
        #expect(environment.sessions.count == 2)
    }

    @Test("Signing out leaves nothing of the account behind")
    func teardownIsComplete() async throws {
        let (environment, transport) = makeEnvironment()
        let session = try await signIn(environment, token: "secret")
        let id = session.id
        let credentials = environment.credentials
        try credentials.setNextcloudCredentials(
            .init(server: base, loginName: "alice", appPassword: "app-password"), for: id)
        try credentials.setPushKeys("{}", for: id)
        AppGroup.defaults.set(Data([1]), forKey: AccountTeardown.pushRegistrationKey(for: id))
        WidgetFavourites.set(true, statusID: "9", accountID: id)
        _ = try await session.supportStore.saveDraft(DraftSnapshot(accountID: id, text: "draft"))

        #expect(await environment.removeAccount(id))

        #expect(try credentials.token(for: id) == nil)
        #expect(try credentials.nextcloudCredentials(for: id) == nil)
        #expect(try credentials.pushKeys(for: id) == nil)
        #expect(AppGroup.defaults.data(forKey: AccountTeardown.pushRegistrationKey(for: id)) == nil)
        #expect(WidgetFavourites.state(statusID: "9", accountID: id) == nil)
        #expect(try await session.supportStore.drafts(accountID: id).isEmpty)
        #expect(try await AccountStore(modelContainer: environment.container).allAccounts().isEmpty)
        #expect(environment.sessions.isEmpty)
        #expect(environment.activeAccountID == nil)
        // Let the cache clear land; it hops onto the transport's actor.
        try await Task.sleep(for: .milliseconds(20))
        #expect(await transport.cacheCleared)
    }

    /// A poll that was out when the account was removed used to come back
    /// and write its notifications into the store the removal had emptied,
    /// for an account that no longer existed — and put its count in the
    /// badge.
    @Test("A poll under way when its account is removed writes nothing")
    func removalStopsPolling() async throws {
        let transport = SlowPollTransport()
        let environment = AppEnvironment(
            container: StoreContainer.make(inMemory: true), transport: transport,
            credentials: CredentialStore(inMemory: true))
        environment.sync.attach(to: environment)
        let session = try await signIn(environment, token: "t")
        let id = session.id

        let poll = Task { await environment.sync.poll(session) }
        // Long enough for the poll to be waiting on the server.
        try await Task.sleep(for: .milliseconds(50))
        #expect(await environment.removeAccount(id))

        #expect(await poll.value == 0)
        #expect(environment.sync.unreadCounts[id] == nil)
        // And a poll that starts afterwards does not go out at all.
        let before = await transport.unreadRequests
        #expect(await environment.sync.poll(session) == 0)
        #expect(await transport.unreadRequests == before)

        let context = ModelContext(environment.container)
        let notifications = try context.fetchCount(
            FetchDescriptor<NotificationRecord>(predicate: #Predicate { $0.accountID == id }))
        #expect(notifications == 0)
    }
}

/// Holds the unread-count request long enough for an account to be removed
/// while it is out.
private actor SlowPollTransport: HTTPTransport {
    let server = MockAPIServer(configuration: .mastodon43, statusCount: 1)
    private(set) var unreadRequests = 0

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path().hasSuffix("notifications/unread_count") == true {
            unreadRequests += 1
            try? await Task.sleep(for: .milliseconds(300))
        }
        return try await server.send(request)
    }

    nonisolated func removeCachedResponses() {}
}

@Suite("When a sign-in really has expired")
@MainActor
struct ReauthenticationCheckTests {
    @Test("Offline is not signed out")
    func offlineDoesNotMark() async throws {
        let (environment, transport) = makeEnvironment()
        let session = try await signIn(environment, token: "t")
        await transport.failVerification(with: .transport(URLError(.notConnectedToInternet)))

        await session.handle(APIError.unauthorised(message: nil))

        #expect(!session.needsReauthentication)
    }

    @Test("A refused token is")
    func refusedTokenMarks() async throws {
        let (environment, transport) = makeEnvironment()
        let session = try await signIn(environment, token: "t")
        await transport.failVerification(with: .unauthorised(message: nil))

        await session.handle(APIError.unauthorised(message: nil))

        #expect(session.needsReauthentication)
    }

    @Test("Ten failures at once ask the server once")
    func concurrentChecksCoalesce() async throws {
        let (environment, transport) = makeEnvironment()
        let session = try await signIn(environment, token: "t")
        // Signing in refreshes the profile in the background, which asks
        // too; that one is not what is counted.
        try await Task.sleep(for: .milliseconds(300))
        let before = await transport.verifyCount
        await transport.failVerification(with: .unauthorised(message: nil))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { await session.handle(APIError.unauthorised(message: nil)) }
            }
        }

        #expect(await transport.verifyCount - before == 1)
        #expect(session.needsReauthentication)
    }
}

@Suite("What signing out reaches outside the store")
struct AccountTeardownTests {
    @Test("The widgets' snapshots and a Focus set for the account go with it")
    func sharedStateRemoved() throws {
        let suite = "aloha-teardown-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory
            .appending(path: "aloha-teardown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        let other = UUID()
        let memories = MemoriesSnapshotStore(directory: root.appending(path: "Widgets"))
        try memories.write(
            MemoriesSnapshot(accountID: id, day: "2026-10-16", memories: []), images: [:])
        let topShelf = TopShelfSnapshotStore(directory: root.appending(path: "TopShelf"))
        try topShelf.write(TopShelfSnapshot(accountID: id, createdAt: Date(), sections: []))
        WidgetFavourites.set(true, statusID: "1", accountID: id, in: defaults)
        WidgetFavourites.set(true, statusID: "2", accountID: other, in: defaults)
        defaults.set(
            try JSONEncoder().encode(FocusFilterState(accountID: id, mentionsOnly: true)),
            forKey: FocusFilterState.key)

        AccountTeardown.removeSharedState(
            for: id, in: defaults, memories: memories, topShelf: topShelf)

        #expect(memories.read() == nil)
        #expect(topShelf.read() == nil)
        #expect(WidgetFavourites.state(statusID: "1", accountID: id, in: defaults) == nil)
        // Somebody else's tap is theirs.
        #expect(WidgetFavourites.state(statusID: "2", accountID: other, in: defaults) == true)
        let focus = try JSONDecoder().decode(
            FocusFilterState.self, from: try #require(defaults.data(forKey: FocusFilterState.key)))
        #expect(focus.accountID == nil)
        #expect(focus.mentionsOnly)
    }
}
