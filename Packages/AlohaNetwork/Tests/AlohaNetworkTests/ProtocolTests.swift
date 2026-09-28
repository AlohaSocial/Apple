// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

@Suite("Link header")
struct LinkHeaderTests {

    @Test("Both relations parse from Mastodon's own form")
    func bothRelations() {
        let raw = """
            <https://cloud.example/api/v1/timelines/home?limit=20&max_id=41>; rel="next", \
            <https://cloud.example/api/v1/timelines/home?limit=20&min_id=60>; rel="prev"
            """
        let link = LinkHeader(parsing: raw)
        #expect(link.next?.query() == "limit=20&max_id=41")
        #expect(link.previous?.query() == "limit=20&min_id=60")
    }

    @Test("A non-root API base survives in the cursor")
    func nonRootBase() {
        // A Nextcloud without the rewrite sends links under the app prefix, and
        // following them verbatim is what keeps paging working there.
        let raw =
            "<https://cloud.example/index.php/apps/social/api/v1/timelines/home?max_id=41>; rel=\"next\""
        let link = LinkHeader(parsing: raw)
        #expect(link.next?.path() == "/index.php/apps/social/api/v1/timelines/home")
    }

    @Test("Filters the caller sent survive into the cursor")
    func filtersSurvive() {
        let raw =
            "<https://cloud.example/api/v1/timelines/public?only_video=true&max_id=9>; rel=\"next\""
        let link = LinkHeader(parsing: raw)
        #expect(link.next?.query()?.contains("only_video=true") == true)
    }

    @Test("A comma inside a query value does not split the header")
    func commaInsideURL() {
        let raw = "<https://cloud.example/api/v1/x?types=a,b,c&max_id=5>; rel=\"next\""
        let link = LinkHeader(parsing: raw)
        #expect(link.next != nil)
        #expect(link.previous == nil)
    }

    @Test("Absent, empty and malformed headers are empty rather than fatal")
    func degenerateForms() {
        #expect(LinkHeader(parsing: nil).isEmpty)
        #expect(LinkHeader(parsing: "").isEmpty)
        #expect(LinkHeader(parsing: "garbage").isEmpty)
        #expect(LinkHeader(parsing: "<not a url; rel=\"next\"").isEmpty)
    }

    @Test("Unquoted and single-quoted rel values parse")
    func relQuoting() {
        #expect(LinkHeader(parsing: "<https://x.test/a>; rel=next").next != nil)
        #expect(LinkHeader(parsing: "<https://x.test/a>; rel='prev'").previous != nil)
    }
}

@Suite("Pagination")
struct PaginationTests {

    @Test("The header decides whether more exists, not the row count")
    func headerWins() {
        let withNext = Paginated(
            value: [1], link: LinkHeader(next: URL(string: "https://x.test/2")), rawCount: 1,
            requestedLimit: 20)
        #expect(withNext.mayHaveMore)

        // A filtered page can be shorter than `limit` while more remain; the
        // server still sends `next`, so the header is authoritative.
        let full = Paginated(value: [1], link: LinkHeader(), rawCount: 20, requestedLimit: 20)
        #expect(full.mayHaveMore)

        let short = Paginated(value: [1], link: LinkHeader(), rawCount: 3, requestedLimit: 20)
        #expect(short.mayHaveMore == false)
    }

    @Test("Anchors produce the right cursor parameter")
    func anchors() {
        #expect(PageAnchor.cold.queryItems.isEmpty)
        #expect(PageAnchor.olderThan("41").queryItems.first?.name == "max_id")
        #expect(PageAnchor.newerThan("60").queryItems.first?.name == "min_id")
        #expect(PageAnchor.immediatelyAfter("7").queryItems.first?.name == "since_id")
    }

    @Test("Limit is clamped to the server's cap of fifty")
    func limitClamping() {
        let endpoint = Endpoint.timelines.timeline(.home, limit: 500)
        #expect(endpoint.query.first { $0.name == "limit" }?.value == "50")
    }
}

@Suite("Endpoint construction")
struct EndpointTests {

    @Test("only_video wins over only_media, since every video is media")
    func videoNarrowingWins() {
        let endpoint = Endpoint.timelines.timeline(
            .home, filters: TimelineFilters(onlyMedia: true, onlyVideo: true))
        let names = endpoint.query.map(\.name)
        #expect(names.contains("only_video"))
        #expect(names.contains("only_media") == false)
    }

    @Test("A false flag is omitted rather than sent as false")
    func falseFlagsAreOmitted() {
        let endpoint = Endpoint.timelines.timeline(.home, filters: .none)
        #expect(endpoint.query.contains { $0.name == "only_media" } == false)
        #expect(endpoint.query.contains { $0.name == "local" } == false)
    }

    @Test("Local narrows the public timeline")
    func localNarrowing() {
        let endpoint = Endpoint.timelines.timeline(.local)
        #expect(endpoint.path == "api/v1/timelines/public/")
        #expect(endpoint.query.contains { $0.name == "local" && $0.value == "true" })
    }

    @Test("A list timeline has a route of its own, not a name")
    func listTimeline() {
        #expect(Endpoint.timelines.timeline(.list(id: "3")).path == "api/v1/timelines/list/3")
    }

    @Test("Hashtags are normalised into the path")
    func hashtagNormalisation() {
        // #NextCloud and nextcloud are one tag to follow, look up and unfollow.
        #expect(
            Endpoint.timelines.timeline(.hashtag(name: "#NextCloud")).path
                == "api/v1/timelines/tag/nextcloud")
        #expect(Endpoint.tags.follow("#Swift").path == "api/v1/tags/swift/follow")
    }

    @Test("Public timelines do not require a token; home does")
    func authenticationRequirements() {
        #expect(Endpoint.timelines.timeline(.federated).requiresAuthentication == false)
        #expect(Endpoint.timelines.timeline(.home).requiresAuthentication)
    }

    @Test("A post carries its idempotency key; an edit does not")
    func idempotency() {
        let draft = StatusPost(text: "Hello", idempotencyKey: "key-1")
        #expect(Endpoint.composing.post(draft).idempotencyKey == "key-1")
        // An edit targets a known id and cannot duplicate, so it needs none.
        #expect(Endpoint.composing.edit("9", draft).idempotencyKey == nil)
    }

    @Test("A poll is dropped when media is attached, as Mastodon requires")
    func pollAndMediaAreExclusive() {
        let draft = StatusPost(
            text: "x", mediaIDs: ["m1"], pollOptions: ["a", "b"])
        let names = draft.formItems.map(\.name)
        #expect(names.contains("media_ids[]"))
        #expect(names.contains { $0.hasPrefix("poll") } == false)
    }

    @Test("Story duration is clamped to the server's 3–30 second window")
    func storyDurationClamping() {
        func duration(_ requested: Int) -> String? {
            guard
                case .form(let items)? = Endpoint.stories.post(
                    mediaID: "m", caption: nil, duration: requested
                ).body
            else { return nil }
            return items.first { $0.name == "duration" }?.value
        }
        #expect(duration(1) == "3")
        #expect(duration(12) == "12")
        #expect(duration(90) == "30")
    }

    @Test("URLs compose onto a non-root API base without losing the prefix")
    func urlComposition() throws {
        let base = URL(string: "https://cloud.example/index.php/apps/social/")!
        let url = try #require(Endpoint.timelines.timeline(.home, limit: 20).url(base: base))
        #expect(url.path() == "/index.php/apps/social/api/v1/timelines/home/")
        #expect(url.query()?.contains("limit=20") == true)
    }
}

@Suite("OAuth")
struct OAuthTests {

    @Test("PKCE produces an unpadded base64url challenge of the right length")
    func pkceShape() {
        let pkce = PKCE()
        #expect(pkce.verifier.count >= 43 && pkce.verifier.count <= 128)
        #expect(pkce.challenge.contains("=") == false)
        #expect(pkce.challenge.contains("+") == false)
        #expect(pkce.challenge.contains("/") == false)
        #expect(pkce.method == "S256")
    }

    @Test("The challenge is the SHA-256 of the verifier, per RFC 7636")
    func pkceKnownAnswer() {
        // The worked example from RFC 7636 appendix B.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(PKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("The authorisation URL carries state and the PKCE challenge")
    func authorisationURL() throws {
        let service = OAuthService(transport: MockAPIServer(configuration: .mastodon43))
        let endpoints = OAuthService.Endpoints.conventional(
            base: URL(string: "https://cloud.example/")!)
        let request = try #require(
            service.makeAuthorisationRequest(endpoints: endpoints, clientID: "abc"))

        let items =
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        #expect(value("response_type") == "code")
        #expect(value("client_id") == "abc")
        #expect(value("redirect_uri") == OAuthService.redirectURI)
        #expect(value("scope") == "read write follow push")
        #expect(value("state") == request.state)
        #expect(value("code_challenge") == request.pkce.challenge)
        #expect(value("code_challenge_method") == "S256")
    }

    @Test("A callback with a mismatched state is refused")
    func stateMismatch() {
        let service = OAuthService(transport: MockAPIServer(configuration: .mastodon43))
        let callback = URL(string: "alohasocial://oauth-callback?code=abc&state=wrong")!

        #expect(throws: OAuthService.CallbackError.self) {
            _ = try service.extractCode(from: callback, expectedState: "right")
        }
    }

    @Test("A redirect that already had a query string still parses")
    func redirectWithExistingQuery() throws {
        // Nextcloud Social appends its parameters to whatever the registered
        // URI already carried, and Elk registers one with a query string.
        let service = OAuthService(transport: MockAPIServer(configuration: .mastodon43))
        let callback = URL(string: "alohasocial://oauth-callback?foo=bar&code=abc&state=s1")!
        #expect(try service.extractCode(from: callback, expectedState: "s1") == "abc")
    }

    @Test("A denial is reported as a denial, not a missing code")
    func denial() {
        let service = OAuthService(transport: MockAPIServer(configuration: .mastodon43))
        let callback = URL(
            string:
                "alohasocial://oauth-callback?error=access_denied&error_description=Nope&state=s1")!

        #expect(throws: OAuthService.CallbackError.self) {
            _ = try service.extractCode(from: callback, expectedState: "s1")
        }
    }

    @Test("Registration and token exchange round-trip against a mock")
    func fullFlow() async throws {
        let server = MockAPIServer(configuration: .nextcloudSocialWithoutRewrite)
        let service = OAuthService(transport: server)
        let base = URL(string: "https://cloud.example.test/index.php/apps/social/")!

        let application = try await service.registerApplication(base: base)
        #expect(application.clientID == "mock-client-id")
        // Always present, always empty on Nextcloud Social: that empty string is
        // the server telling the client not to offer Web Push.
        #expect(application.vapidKey == "")

        let endpoints = await service.discoverEndpoints(base: base)
        #expect(endpoints.supportsPKCE)

        let token = try await service.exchange(
            code: "code", endpoints: endpoints, clientID: "mock-client-id",
            clientSecret: "mock-client-secret", verifier: PKCE().verifier)
        #expect(token.accessToken == "mock-access-token")

        // RFC 6749 §4.1.3 has no `scope` on this request, and Nextcloud Social
        // refuses one that sends it.
        let sentToToken = await server.requestLog.filter { $0.path.hasSuffix("oauth/token") }
        #expect(sentToToken.count == 1)
    }
}

@Suite("Error mapping")
struct ErrorTests {

    @Test("A revoked token is a re-authentication state, not a fatal error")
    func revokedToken() {
        let body = Data(#"{"error":"the access_token was revoked"}"#.utf8)
        let error = APIError.from(status: 401, data: body, headers: [:])

        guard case .unauthorised(let message)? = error else {
            Issue.record("expected .unauthorised")
            return
        }
        #expect(message == "the access_token was revoked")
        #expect(error?.requiresReauthentication == true)
        #expect(error?.isTransient == false)
    }

    @Test("A 422's message is preserved for showing verbatim")
    func unprocessable() {
        let body = Data(#"{"error":"Validation failed: Text is too long"}"#.utf8)
        guard
            case .unprocessable(let message)? = APIError.from(status: 422, data: body, headers: [:])
        else {
            Issue.record("expected .unprocessable")
            return
        }
        #expect(message == "Validation failed: Text is too long")
    }

    @Test("Retry-After is honoured where the server sent one")
    func rateLimit() {
        guard
            case .rateLimited(let retryAfter)? = APIError.from(
                status: 429, data: Data(), headers: ["Retry-After": "30"])
        else {
            Issue.record("expected .rateLimited")
            return
        }
        #expect(retryAfter == 30)
    }

    @Test("A 2xx is not an error")
    func successIsNotAnError() {
        #expect(APIError.from(status: 200, data: Data(), headers: [:]) == nil)
        #expect(APIError.from(status: 204, data: Data(), headers: [:]) == nil)
    }
}
