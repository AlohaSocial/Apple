// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import OSLog

/// App registration, authorisation and token exchange.
///
/// Nextcloud Social stores authorisations in a table of their own, so one
/// registered app holds many tokens: a second person signing in no longer
/// revokes the first, and revoking one token no longer signs everybody out.
/// This service relies on that (docs/03 §4).
public struct OAuthService: Sendable {
    public static let clientName = "Aloha Social"
    public static let redirectURI = "alohasocial://oauth-callback"
    public static let outOfBandRedirectURI = "urn:ietf:wg:oauth:2.0:oob"
    public static let website = "https://github.com/nextcloud/AlohaSocial"
    /// Coarse grants covering every granular scope Nextcloud Social checks
    /// (`read:lists`, `read:notifications`, `write:notifications`,
    /// `read:stories`, `write:stories`). `push` costs nothing on a server with
    /// no Web Push and is needed on servers that have it.
    public static let scopes = "read write follow push"

    private let transport: any HTTPTransport
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "oauth")

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    // MARK: - Discovery

    public struct Endpoints: Sendable, Hashable {
        public var authorization: URL
        public var token: URL
        public var revocation: URL
        public var supportsPKCE: Bool

        public init(authorization: URL, token: URL, revocation: URL, supportsPKCE: Bool = true) {
            self.authorization = authorization
            self.token = token
            self.revocation = revocation
            self.supportsPKCE = supportsPKCE
        }

        /// What every Mastodon-compatible server serves, used when the
        /// discovery document is absent.
        public static func conventional(base: URL) -> Endpoints {
            Endpoints(
                authorization: base.appending(path: "oauth/authorize"),
                token: base.appending(path: "oauth/token"),
                revocation: base.appending(path: "oauth/revoke")
            )
        }
    }

    public func discoverEndpoints(base: URL) async -> Endpoints {
        let fallback = Endpoints.conventional(base: base)
        var request = URLRequest(
            url: base.appending(path: ".well-known/oauth-authorization-server"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await transport.send(request),
            (200..<300).contains(response.statusCode),
            let metadata = try? AlohaJSON.decoder.decode(OAuthServerMetadata.self, from: data)
        else { return fallback }

        return Endpoints(
            authorization: metadata.authorizationEndpoint ?? fallback.authorization,
            token: metadata.tokenEndpoint ?? fallback.token,
            revocation: metadata.revocationEndpoint ?? fallback.revocation,
            supportsPKCE: metadata.supportsPKCE
        )
    }

    // MARK: - Registration

    /// `POST /api/v1/apps`. Nextcloud Social splits `redirect_uris` on
    /// newlines, as Mastodon's own API does; one is sent.
    public func registerApplication(
        base: URL, redirectURI: String = OAuthService.redirectURI
    ) async throws -> OAuthApplication {
        var request = URLRequest(url: base.appending(path: "api/v1/apps"))
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_name", value: Self.clientName),
            URLQueryItem(name: "redirect_uris", value: redirectURI),
            URLQueryItem(name: "scopes", value: Self.scopes),
            URLQueryItem(name: "website", value: Self.website),
        ]
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await transport.send(request)
        if let error = APIError.from(
            status: response.statusCode, data: data, headers: response.allHeaderFields)
        {
            throw error
        }
        do {
            return try AlohaJSON.decoder.decode(OAuthApplication.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error, context: "api/v1/apps")
        }
    }

    // MARK: - Authorisation

    public struct AuthorisationRequest: Sendable {
        public var url: URL
        public var state: String
        public var pkce: PKCE
        public var redirectURI: String
    }

    public func makeAuthorisationRequest(
        endpoints: Endpoints,
        clientID: String,
        redirectURI: String = OAuthService.redirectURI
    ) -> AuthorisationRequest? {
        let state = Data.randomBase64URL(byteCount: 32)
        let pkce = PKCE()

        guard
            var components = URLComponents(
                url: endpoints.authorization, resolvingAgainstBaseURL: false)
        else { return nil }

        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        if endpoints.supportsPKCE {
            items.append(URLQueryItem(name: "code_challenge", value: pkce.challenge))
            items.append(URLQueryItem(name: "code_challenge_method", value: pkce.method))
        }
        components.queryItems = (components.queryItems ?? []) + items

        guard let url = components.url else { return nil }
        return AuthorisationRequest(url: url, state: state, pkce: pkce, redirectURI: redirectURI)
    }

    public enum CallbackError: Error, Sendable {
        case stateMismatch
        case denied(String?)
        case missingCode
    }

    /// Reads the code out of the redirect. Nextcloud Social appends its
    /// parameters to whatever query string and fragment the registered URI
    /// already had, so parsing has to tolerate both.
    public func extractCode(from callback: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            throw CallbackError.missingCode
        }
        let items = components.queryItems ?? []

        if let error = items.first(where: { $0.name == "error" })?.value {
            throw CallbackError.denied(
                items.first(where: { $0.name == "error_description" })?.value ?? error)
        }
        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw CallbackError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw CallbackError.missingCode
        }
        return code
    }

    // MARK: - Token exchange

    /// There is deliberately **no `scope` parameter** here. RFC 6749 §4.1.3 has
    /// none, and Nextcloud Social refuses requests that send one against a
    /// stale app row — the code names the authorisation, and what the token
    /// carries is what the person granted (docs/03 §4).
    ///
    /// A code is spent in the same statement that writes the token, so a
    /// duplicated exchange fails safely. Never retry this automatically.
    public func exchange(
        code: String,
        endpoints: Endpoints,
        clientID: String,
        clientSecret: String,
        redirectURI: String = OAuthService.redirectURI,
        verifier: String?
    ) async throws -> OAuthToken {
        var request = URLRequest(url: endpoints.token)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var items = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        if let verifier { items.append(URLQueryItem(name: "code_verifier", value: verifier)) }

        var components = URLComponents()
        components.queryItems = items
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await transport.send(request)
        if let error = APIError.from(
            status: response.statusCode, data: data, headers: response.allHeaderFields)
        {
            throw error
        }
        do {
            return try AlohaJSON.decoder.decode(OAuthToken.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error, context: "oauth/token")
        }
    }

    /// Revoking takes one authorisation rather than the app's only token, so a
    /// sign-out on one device leaves the others signed in.
    public func revoke(
        token: String, endpoints: Endpoints, clientID: String, clientSecret: String
    ) async throws {
        var request = URLRequest(url: endpoints.revocation)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "token", value: token),
        ]
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await transport.send(request)
        if let error = APIError.from(
            status: response.statusCode, data: data, headers: response.allHeaderFields)
        {
            throw error
        }
    }
}
