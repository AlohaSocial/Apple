// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import Testing

@testable import AlohaUI

@Suite("The send queue")
@MainActor
struct SendQueueTests {

    @Test("Queued posts go out in order, with the key they were saved with")
    func drainsInOrder() async throws {
        let (session, transport) = try await makeSession()
        for (index, text) in ["first", "second"].enumerated() {
            _ = try await session.supportStore.saveDraft(
                DraftSnapshot(
                    accountID: session.id, text: text, idempotencyKey: "key-\(index)",
                    queuedForSend: true, threadIndex: index))
        }

        let sent = await SendQueue.drain(session: session)

        #expect(sent == 2)
        let posts = await transport.posts
        #expect(posts.map(\.text) == ["first", "second"])
        // The saved key, not a new one: a first attempt that did land is then
        // recognised by the server instead of posted twice.
        #expect(posts.map(\.idempotencyKey) == ["key-0", "key-1"])
        #expect(try await session.supportStore.drafts(accountID: session.id).isEmpty)
    }

    @Test("Still offline: the queue stops and keeps everything")
    func transientFailureKeepsQueue() async throws {
        let (session, transport) = try await makeSession()
        await transport.failPosts(with: .transport(URLError(.notConnectedToInternet)))
        for index in 0..<2 {
            _ = try await session.supportStore.saveDraft(
                DraftSnapshot(
                    accountID: session.id, text: "post \(index)", queuedForSend: true,
                    threadIndex: index))
        }

        let sent = await SendQueue.drain(session: session)

        #expect(sent == 0)
        // One attempt, not two: the second must not overtake the first.
        #expect(await transport.posts.count == 1)
        #expect(try await session.supportStore.queuedDrafts(accountID: session.id).count == 2)
    }

    @Test("A refusal takes that post off the queue with the server's reason")
    func refusalLeavesDraft() async throws {
        let (session, transport) = try await makeSession()
        await transport.failPosts(with: .unprocessable(message: "Text is too long"))
        let id = try await session.supportStore.saveDraft(
            DraftSnapshot(accountID: session.id, text: "long", queuedForSend: true))

        _ = await SendQueue.drain(session: session)

        #expect(try await session.supportStore.queuedDrafts(accountID: session.id).isEmpty)
        let kept = try #require(try await session.supportStore.drafts(accountID: session.id).first)
        #expect(kept.id == id)
        #expect(kept.lastSendError == "Text is too long")
    }

    @Test("A queued thread posts its segments as a chain")
    func threadChains() async throws {
        let (session, transport) = try await makeSession()
        _ = try await session.supportStore.saveDraft(
            DraftSnapshot(
                accountID: session.id, text: "one", queuedForSend: true,
                threadSegments: ["two", "three"]))

        #expect(await SendQueue.drain(session: session) == 1)

        let posts = await transport.posts
        #expect(posts.map(\.text) == ["one", "two", "three"])
        #expect(posts[0].inReplyToID == nil)
        #expect(posts[1].inReplyToID != nil)
        #expect(posts[2].inReplyToID != posts[1].inReplyToID)
    }
}

@Suite("Drafts and redrafts in the composer")
@MainActor
struct ComposerRestoreTests {

    @Test("A reopened draft saves back as the same draft, unchanged")
    func draftRoundTrip() async throws {
        let (session, _) = try await makeSession()
        let draft = DraftSnapshot(
            accountID: session.id, text: "Half a thought", spoilerText: "politics",
            visibility: .private, language: "de", inReplyToID: "40",
            pollOptions: ["Yes", "No"], pollMultiple: true,
            scheduledAt: Date(timeIntervalSince1970: 1_900_000_000),
            idempotencyKey: "kept", quotedID: "41", threadSegments: ["and more"])

        let model = ComposerModel(session: session, draft: draft)
        let saved = model.draftSnapshot

        #expect(saved.id == draft.id)
        #expect(saved.text == draft.text)
        #expect(saved.spoilerText == "politics")
        #expect(saved.visibility == .private)
        #expect(saved.language == "de")
        #expect(saved.inReplyToID == "40")
        #expect(saved.quotedID == "41")
        #expect(saved.pollOptions == ["Yes", "No"])
        #expect(saved.pollMultiple)
        #expect(saved.scheduledAt == draft.scheduledAt)
        #expect(saved.threadSegments == ["and more"])
        // Untouched words keep their key.
        #expect(saved.idempotencyKey == "kept")
    }

    @Test("Editing a reopened draft gives it a new key")
    func editedDraftNewKey() async throws {
        let (session, _) = try await makeSession()
        let model = ComposerModel(
            session: session,
            draft: DraftSnapshot(accountID: session.id, text: "Hi", idempotencyKey: "kept"))

        model.text = "Hi there"

        #expect(model.draftSnapshot.idempotencyKey != "kept")
    }

    @Test("A redraft starts from the source text and the post's settings")
    func redraftPrefill() async throws {
        let (session, _) = try await makeSession()
        var status = Status(id: "77", account: Account(id: "1", username: "alice", acct: "alice"))
        status.visibility = .unlisted
        status.language = "fr"
        status.inReplyToID = "70"
        let source = try AlohaJSON.decoder.decode(
            StatusSource.self,
            from: Data(#"{"id":"77","text":"Bonjour *monde*","spoiler_text":"cw"}"#.utf8))

        let model = ComposerModel(session: session, redrafting: status, source: source)

        #expect(model.text == "Bonjour *monde*")
        #expect(model.spoilerText == "cw")
        #expect(model.showsContentWarningField)
        #expect(model.visibility == .unlisted)
        #expect(model.language == "fr")
        #expect(model.redrafting?.id == "77")
        #expect(model.draftSnapshot.inReplyToID == "70")
    }

    @Test("A redraft deletes the original only after the new post is made")
    func redraftDeletesAfterPosting() async throws {
        let (session, transport) = try await makeSession()
        let status = Status(id: "77", account: Account(id: "1", username: "alice", acct: "alice"))
        let source = try AlohaJSON.decoder.decode(
            StatusSource.self, from: Data(#"{"id":"77","text":"Again","spoiler_text":""}"#.utf8))
        let model = ComposerModel(session: session, redrafting: status, source: source)

        #expect(await model.post(skippingAltTextCheck: true))

        let log = await transport.log
        let post = try #require(log.firstIndex { $0 == "POST api/v1/statuses" })
        let delete = try #require(log.firstIndex { $0 == "DELETE api/v1/statuses/77" })
        #expect(post < delete)
    }
}

// MARK: - Support

@MainActor
private func makeSession() async throws -> (AccountSession, RecordingTransport) {
    let server = MockAPIServer(configuration: .mastodon43, statusCount: 3)
    let transport = RecordingTransport(server: server)
    let container = StoreContainer.make(inMemory: true)
    let accounts = AccountStore(modelContainer: container)
    let base = try #require(URL(string: "https://cloud.example.test/"))
    let snapshot = try await accounts.addAccount(
        instanceHost: "cloud.example.test", apiBase: base,
        account: Account(id: "1", username: "alice", acct: "alice"),
        capabilities: .minimal(apiBase: base))
    let session = AccountSession(
        snapshot: snapshot, token: "test-token", transport: transport,
        timelines: TimelineStore(modelContainer: container),
        support: SupportStore(modelContainer: container), accounts: accounts)
    return (session, transport)
}

/// The mock server, with every request written down and posts made to fail
/// on demand.
private actor RecordingTransport: HTTPTransport {
    struct Post: Sendable {
        var text: String?
        var inReplyToID: String?
        var idempotencyKey: String?
    }

    let server: MockAPIServer
    private(set) var posts: [Post] = []
    private(set) var log: [String] = []
    private var postFailure: APIError?

    init(server: MockAPIServer) { self.server = server }

    func failPosts(with error: APIError) { postFailure = error }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path().trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        log.append("\(method) \(path)")

        if method == "POST", path == "api/v1/statuses" {
            let fields = Self.form(request.httpBody)
            posts.append(
                Post(
                    text: fields["status"], inReplyToID: fields["in_reply_to_id"],
                    idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key")))
            if let postFailure { throw postFailure }
        }
        return try await server.send(request)
    }

    private static func form(_ body: Data?) -> [String: String] {
        guard let body, let string = String(data: body, encoding: .utf8) else { return [:] }
        var components = URLComponents()
        components.percentEncodedQuery = string.replacingOccurrences(of: "+", with: "%20")
        var fields: [String: String] = [:]
        for item in components.queryItems ?? [] { fields[item.name] = item.value }
        return fields
    }
}
