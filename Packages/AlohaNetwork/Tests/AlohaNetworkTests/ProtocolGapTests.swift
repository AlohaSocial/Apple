// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaNetwork

/// Forwards to a real mock, and remembers every request it was handed, body
/// included — what the request log, which keeps only method and path, cannot
/// show.
private actor RecordingTransport: HTTPTransport {
    private let inner: MockAPIServer
    private(set) var requests: [URLRequest] = []

    init(_ inner: MockAPIServer) { self.inner = inner }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try await inner.send(request)
    }
}

/// Never answers the requests `hangs` picks, until it is cancelled; forwards
/// the rest. A server that accepts the connection and then says nothing.
private struct HangingTransport: HTTPTransport {
    let inner: MockAPIServer?
    let hangs: @Sendable (URL) -> Bool

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let url = request.url, hangs(url) || inner == nil {
            try await Task.sleep(for: .seconds(120))
            throw URLError(.timedOut)
        }
        guard let inner else { throw URLError(.cannotConnectToHost) }
        return try await inner.send(request)
    }
}

@Suite("OAuth: the cases docs/12 lists")
struct OAuthGapTests {
    private let service = OAuthService(transport: MockAPIServer(configuration: .mastodon43))

    @Test("A redirect that carries its parameters in the fragment parses")
    func fragmentRedirect() throws {
        let callback = URL(string: "alohasocial://oauth-callback#code=abc&state=s1")!
        #expect(try service.extractCode(from: callback, expectedState: "s1") == "abc")
    }

    @Test("A fragment with encoded characters keeps them")
    func fragmentWithEncodedValues() throws {
        let callback = URL(string: "alohasocial://oauth-callback#code=a%2Bb%26c&state=s%201")!
        #expect(try service.extractCode(from: callback, expectedState: "s 1") == "a+b&c")
    }

    @Test("The query wins when both carry parameters")
    func queryBeatsFragment() throws {
        let callback = URL(string: "alohasocial://oauth-callback?code=fromQuery&state=s1#code=x")!
        #expect(try service.extractCode(from: callback, expectedState: "s1") == "fromQuery")
    }

    @Test("A denial in the fragment is a denial")
    func fragmentDenial() {
        let callback = URL(string: "alohasocial://oauth-callback#error=access_denied&state=s1")!
        #expect(throws: OAuthService.CallbackError.self) {
            _ = try service.extractCode(from: callback, expectedState: "s1")
        }
    }

    @Test("The token request's body carries no scope, and carries what it must")
    func tokenBodyHasNoScope() async throws {
        let recorder = RecordingTransport(
            MockAPIServer(configuration: .nextcloudSocialWithoutRewrite))
        let service = OAuthService(transport: recorder)
        let base = URL(string: "https://cloud.example.test/index.php/apps/social/")!
        let endpoints = await service.discoverEndpoints(base: base)

        _ = try await service.exchange(
            code: "the-code", endpoints: endpoints, clientID: "mock-client-id",
            clientSecret: "mock-client-secret", verifier: "v")

        let token = try #require(
            await recorder.requests.first { $0.url?.path().hasSuffix("oauth/token") == true })
        let body = String(decoding: token.httpBody ?? Data(), as: UTF8.self)
        var parsed = URLComponents()
        parsed.percentEncodedQuery = body
        let names = Set((parsed.queryItems ?? []).map(\.name))
        #expect(!names.contains("scope"))
        #expect(
            names.isSuperset(of: [
                "grant_type", "code", "client_id", "client_secret", "redirect_uri", "code_verifier",
            ]))
    }
}

@Suite("Discovery: time limits and the re-probe")
struct DiscoveryTimingTests {
    private let address = ServerProbe.ServerAddress(typed: "cloud.example.test")!

    @Test("A server that never answers fails within the budget, naming what was tried")
    func everythingHangs() async {
        let probe = ServerProbe(
            transport: HangingTransport(inner: nil) { _ in true },
            perCandidateTimeout: .milliseconds(200), totalBudget: .milliseconds(400))
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await probe.discover(address)
            Issue.record("expected the probe to fail")
        } catch let failure as ServerProbe.ProbeFailure {
            guard case .noCandidateAnswered(let attempted) = failure else {
                Issue.record("expected noCandidateAnswered, got \(failure)")
                return
            }
            #expect(attempted.count == 3)
        } catch {
            Issue.record("unexpected error \(error)")
        }
        // Well under the two minutes the transport would hang for.
        #expect(clock.now - start < .seconds(5))
    }

    @Test("When the best candidate hangs, the next one that answered wins at the deadline")
    func bestSoFarWinsAtTheDeadline() async throws {
        let server = MockAPIServer(configuration: .nextcloudSocialWithoutRewrite)
        // The root candidate (rank 1) hangs instead of answering 404.
        let probe = ServerProbe(
            transport: HangingTransport(inner: server) { url in
                url.path() == "/api/v2/instance" || url.path() == "/api/v1/instance/"
            },
            perCandidateTimeout: .seconds(30), totalBudget: .milliseconds(500))
        let outcome = try await probe.discover(address)
        #expect(outcome.apiBase.absoluteString.hasSuffix("/index.php/apps/social/"))
        #expect(outcome.winningCandidate.rank == 2)
    }

    @Test("Without a hang, the probe does not wait for the budget")
    func noWaitWhenEveryoneAnswered() async throws {
        let probe = ServerProbe(
            transport: MockAPIServer(configuration: .nextcloudSocialWithoutRewrite),
            perCandidateTimeout: .seconds(30), totalBudget: .seconds(30))
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = try await probe.discover(address)
        #expect(outcome.winningCandidate.rank == 2)
        #expect(clock.now - start < .seconds(5))
    }

    @Test("The re-probe trigger: the stored root base stops answering after the rewrite goes")
    func reprobeFindsTheMovedBase() async throws {
        // Signed in while the rewrite existed, so the stored base is the root.
        let storedBase = URL(string: "https://cloud.example.test/")!
        let probe = ServerProbe(
            transport: MockAPIServer(configuration: .nextcloudSocialWithoutRewrite))

        // What sets the re-probe off: the instance route fails at the stored base.
        #expect(await probe.fetchInstance(base: storedBase) == nil)

        // And what the re-probe finds, from the stored base alone.
        let outcome = try await probe.discover(ServerProbe.ServerAddress(apiBase: storedBase))
        #expect(outcome.apiBase != storedBase)
        #expect(outcome.apiBase.absoluteString.hasSuffix("/index.php/apps/social/"))
    }

    @Test("A private-network http base is probed again over http, port and all")
    func reprobeKeepsSchemeAndPort() {
        let stored = URL(string: "http://192.168.1.20:8080/index.php/apps/social/")!
        let address = ServerProbe.ServerAddress(apiBase: stored)
        let bases = ServerProbe.candidates(for: address).map(\.base.absoluteString)
        #expect(bases.allSatisfy { $0.hasPrefix("http://192.168.1.20:8080/") })
    }

    @Test("A failing account re-probes at most once an hour")
    func reprobeThrottle() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(ServerProbe.mayReprobe(lastAttempt: nil, now: now))
        #expect(!ServerProbe.mayReprobe(lastAttempt: now.addingTimeInterval(-59 * 60), now: now))
        #expect(ServerProbe.mayReprobe(lastAttempt: now.addingTimeInterval(-60 * 60), now: now))
    }

    @Test("A re-probe follows a move on the same host, never to another one")
    func reprobeStaysOnHost() {
        let stored = URL(string: "https://example.com/index.php/apps/social/")!
        func adopts(_ found: String) -> Bool {
            ServerProbe.mayAdopt(apiBase: URL(string: found)!, replacing: stored)
        }
        #expect(adopts("https://example.com/apps/social/"))
        #expect(adopts("https://EXAMPLE.com:8443/apps/social/"))
        #expect(!adopts("https://social.example.com/apps/social/"))
        #expect(!adopts("https://elsewhere.test/index.php/apps/social/"))
        #expect(!adopts("http://example.com/index.php/apps/social/"))

        let local = URL(string: "http://192.168.1.20/index.php/apps/social/")!
        #expect(
            ServerProbe.mayAdopt(
                apiBase: URL(string: "https://192.168.1.20/index.php/apps/social/")!,
                replacing: local))
    }
}
