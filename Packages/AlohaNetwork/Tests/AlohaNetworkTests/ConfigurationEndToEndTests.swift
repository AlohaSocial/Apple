// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

/// The three things a person does first — read the home timeline, post, read
/// their notifications — against every server shape the mock can take
/// (docs/12 §2: "every one of those configurations must produce a working
/// app"). The no-rewrite case is the one that matters most.
@Suite("End to end, per server configuration")
struct ConfigurationEndToEndTests {
    /// A client pointed where that configuration actually serves the API, as
    /// discovery would have left it.
    private func client(_ configuration: MockAPIServer.Configuration) async -> APIClient {
        let server = MockAPIServer(configuration: configuration)
        let prefix = await server.apiPrefix
        let host = await server.host
        let base = URL(string: "https://\(host)\(prefix)")!
        return APIClient(
            accountID: UUID(), apiBase: base, accessToken: "token", transport: server)
    }

    static let working: [MockAPIServer.Configuration] = [
        .nextcloudSocialWithoutRewrite, .nextcloudSocialWithRewrite, .mastodon43, .coreOnly,
    ]

    // MARK: - Home timeline

    @Test("The home timeline loads in full", arguments: working)
    func homeTimeline(_ configuration: MockAPIServer.Configuration) async throws {
        let page = try await client(configuration).page(
            LossyArray<Status>.self, from: Endpoint.timelines.timeline(.home), limit: 20)
        #expect(!page.value.elements.isEmpty)
        #expect(page.value.failures.isEmpty)
    }

    @Test("A page with a malformed post keeps every other post")
    func malformedTimeline() async throws {
        let page = try await client(.malformedEntities).page(
            LossyArray<Status>.self, from: Endpoint.timelines.timeline(.home), limit: 20)
        #expect(page.value.failures.count == 1)
        #expect(page.value.failures.first?.index == 2)
        #expect(page.value.elements.count == page.rawCount - 1)
    }

    @Test("A rate-limited server says so, rather than failing some other way")
    func rateLimitedTimeline() async {
        await #expect(throws: APIError.self) {
            _ = try await client(.rateLimited).page(
                LossyArray<Status>.self, from: Endpoint.timelines.timeline(.home), limit: 20)
        }
        do {
            _ = try await client(.rateLimited).decode(
                LossyArray<Status>.self, from: Endpoint.timelines.timeline(.home))
        } catch let error as APIError {
            guard case .rateLimited = error else {
                Issue.record("expected .rateLimited, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    // MARK: - Posting

    @Test("A post goes out and comes back as a status", arguments: working)
    func post(_ configuration: MockAPIServer.Configuration) async throws {
        let draft = StatusPost(
            text: "Aloha from \(configuration)", idempotencyKey: UUID().uuidString)
        let status = try await client(configuration).decode(
            Status.self, from: Endpoint.composing.post(draft))
        #expect(!status.id.isEmpty)
    }

    @Test("Posting to a rate-limited server is refused as rate-limited")
    func rateLimitedPost() async {
        let draft = StatusPost(text: "Aloha", idempotencyKey: UUID().uuidString)
        do {
            _ = try await client(.rateLimited).decode(
                Status.self, from: Endpoint.composing.post(draft))
            Issue.record("expected the post to be refused")
        } catch let error as APIError {
            guard case .rateLimited = error else {
                Issue.record("expected .rateLimited, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    // MARK: - Notifications

    @Test("The flat notifications list loads", arguments: working)
    func notifications(_ configuration: MockAPIServer.Configuration) async throws {
        let page = try await client(configuration).decode(
            LossyArray<MastodonNotification>.self, from: Endpoint.notifications.flat())
        #expect(page.failures.isEmpty)
    }

    @Test("A core-only server 404s grouped notifications, so the flat list is the fallback")
    func coreOnlyHasNoGroupedNotifications() async throws {
        let client = await client(.coreOnly)
        do {
            _ = try await client.send(Endpoint.notifications.grouped())
            Issue.record("expected the grouped route to be missing")
        } catch let error as APIError {
            guard case .notFound = error else {
                Issue.record("expected .notFound, got \(error)")
                return
            }
        }
        let flat = try await client.decode(
            LossyArray<MastodonNotification>.self, from: Endpoint.notifications.flat())
        #expect(flat.failures.isEmpty)
    }
}
